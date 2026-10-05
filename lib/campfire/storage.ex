defmodule Campfire.Storage do
  @moduledoc """
  Active Storage, compatible with the Rails app's records and disk layout (SPEC §2.4, §10):
  blobs in `{root}/{key[0,2]}/{key[2,4]}/{key}`, variants as `VariantRecord`s whose `image`
  attachment is the generated blob, URLs signed as Rails signs them.

  Files are written before the database rows that point at them (a crash leaves an orphan
  file, never a row without a file), and image processing happens outside the writer's
  transaction.
  """
  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Schema.Timestamp
  alias Campfire.Signing
  alias Campfire.Storage.{Attachment, Blob, Files, Variation, VariantRecord}

  @thumb_limit [1200, 800]

  def root, do: Application.fetch_env!(:campfire, :storage_root)

  @doc "Where a blob's bytes live."
  def path(%Blob{key: key}), do: path(key)

  def path(<<a::binary-size(2), b::binary-size(2), _::binary>> = key),
    do: Path.join([root(), a, b, key])

  # 28 characters of [0-9a-z], as `has_secure_token` with base36.
  @alphabet ~c"0123456789abcdefghijklmnopqrstuvwxyz"
  def generate_key do
    for <<byte <- :crypto.strong_rand_bytes(28)>>,
      into: "",
      do: <<Enum.at(@alphabet, rem(byte, 36))>>
  end

  ## Signed ids and URLs

  def signed_blob_id(blob_id) when is_integer(blob_id),
    do: blob_id |> Signing.envelope("blob_id") |> Signing.sign("ActiveStorage", :sha, :strict)

  def verify_blob_id(signed) do
    with {:ok, json} <- Signing.verify(signed, "ActiveStorage", :sha, :strict),
         {:ok, id} when is_integer(id) <- Signing.open_envelope(json, "blob_id") do
      {:ok, id}
    else
      _ -> :error
    end
  end

  @doc "`rails_blob_path(blob)`; `disposition: \"attachment\"` for downloads."
  def blob_path(%Blob{} = blob, opts \\ []) do
    path =
      "/rails/active_storage/blobs/redirect/#{segment(signed_blob_id(blob.id))}/#{Files.escape_path(blob.filename)}"

    if opts[:disposition], do: path <> "?disposition=" <> opts[:disposition], else: path
  end

  @doc "`url_for(blob.representation(transformations))`, without the host."
  def representation_path(%Blob{} = blob, transformations) do
    "/rails/active_storage/representations/redirect/#{segment(signed_blob_id(blob.id))}/" <>
      "#{segment(Variation.key(transformations))}/#{Files.escape_path(blob.filename)}"
  end

  # Signed values are base64: `/` must be escaped in a path segment, `+` and `=` may stay.
  defp segment(value), do: String.replace(value, "/", "%2F")

  ## Kinds of blobs

  def variable?(%Blob{content_type: type}), do: Files.variable?(type)
  def video?(%Blob{content_type: type}), do: Files.video?(type)

  @doc "The `:thumb` variant of a message attachment: fit within 1200×800, keeping web formats."
  def thumb(%Blob{} = blob), do: [format: format(blob), resize_to_limit: @thumb_limit]

  @doc "A video's poster: the `{format: :webp, resize_to_limit: [1200, 800]}` of its preview image."
  def poster, do: [format: {:sym, "webp"}, resize_to_limit: @thumb_limit]

  # ActiveStorage::Blob#format/default_variant_format: web images keep theirs (as a string,
  # spelled as the filename spells it), everything else becomes :png.
  defp format(%Blob{content_type: type, filename: filename}) do
    if Files.web_image?(type) do
      {_, ext} = Files.split(filename)

      cond do
        ext != "" and MIME.type(String.downcase(ext)) == type -> ext
        true -> type |> MIME.extensions() |> preferred_extension(type)
      end
    else
      {:sym, "png"}
    end
  end

  defp preferred_extension(_, "image/jpeg"), do: "jpeg"
  defp preferred_extension([ext | _], _), do: ext

  ## Upload

  @doc """
  Stores an uploaded file as a new (unsaved) blob: copies it into place, checksums it, sniffs its
  type and reads image dimensions. Insert it with `insert_blob!/1`.
  """
  def store_upload(%Plug.Upload{path: tmp, filename: filename, content_type: declared}) do
    filename = Files.sanitize(filename || "file")
    content_type = Files.content_type(tmp, filename, declared)
    key = generate_key()
    dest = path(key)

    File.mkdir_p!(Path.dirname(dest))
    File.cp!(tmp, dest)
    %{size: size} = File.stat!(dest)

    %Blob{
      key: key,
      filename: filename,
      content_type: content_type,
      byte_size: size,
      checksum: file_checksum(dest),
      service_name: "local",
      metadata: analyze(dest, content_type)
    }
  end

  defp analyze(path, content_type) do
    if Files.variable?(content_type) do
      case Files.image_dimensions(path) do
        {:ok, w, h} -> %{"identified" => true, "width" => w, "height" => h, "analyzed" => true}
        :error -> %{"identified" => true, "analyzed" => true}
      end
    else
      %{"identified" => true, "analyzed" => true}
    end
  end

  defp file_checksum(path) do
    path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode64()
  end

  def insert_blob!(%Blob{} = blob), do: Repo.insert!(%{blob | created_at: Timestamp.utc_now()})

  def attach!(%Blob{id: blob_id}, record_type, record_id, name) do
    Repo.insert!(%Attachment{
      blob_id: blob_id,
      record_type: record_type,
      record_id: record_id,
      name: name,
      created_at: Timestamp.utc_now()
    })
  end

  ## Variants

  @doc """
  Renders a variant of `blob` into a new (unsaved) blob: `{:ok, blob}`, or `:error` when the
  source can't be processed. Only `resize_to_limit` and `format` are supported.
  """
  def render_variant(%Blob{} = source, transformations) do
    format = transformations |> Keyword.fetch!(:format) |> format_name()
    [w, h] = Keyword.get(transformations, :resize_to_limit, [10_000_000, 10_000_000])

    with {:ok, image} <-
           Vix.Vips.Operation.thumbnail(path(source), w, height: h, size: :VIPS_SIZE_DOWN),
         {:ok, bytes} <- Vix.Vips.Image.write_to_buffer(image, ".#{format}[strip]") do
      key = generate_key()
      dest = path(key)
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, bytes)
      {base, _} = Files.split(source.filename)

      {:ok,
       %Blob{
         key: key,
         filename: "#{base}.#{format}",
         content_type: MIME.type(format),
         byte_size: byte_size(bytes),
         checksum: :crypto.hash(:md5, bytes) |> Base.encode64(),
         service_name: "local",
         metadata: %{"identified" => true}
       }}
    else
      _ -> :error
    end
  end

  defp format_name({:sym, f}), do: f
  defp format_name(f) when is_binary(f), do: f

  @doc "Records `variant` (rendered by `render_variant/2`) as the variant of `source`. In a transaction."
  def insert_variant!(%Blob{id: source_id}, transformations, %Blob{} = variant) do
    record =
      Repo.insert!(
        %VariantRecord{blob_id: source_id, variation_digest: Variation.digest(transformations)},
        on_conflict: :nothing
      )

    # (blob_id, variation_digest) is unique: someone else's variant is already recorded.
    if record.id == nil, do: Repo.rollback(:exists)

    variant = insert_blob!(variant)
    attach!(variant, "ActiveStorage::VariantRecord", record.id, "image")
    variant
  end

  @doc "The stored variant blob of `blob_id` for any spelling of `transformations`, or `nil`."
  def find_variant(blob_id, transformations) do
    Replica.one(
      from b in Blob,
        join: a in Attachment,
        on:
          a.blob_id == b.id and a.record_type == "ActiveStorage::VariantRecord" and
            a.name == "image",
        join: v in VariantRecord,
        on: v.id == a.record_id,
        where:
          v.blob_id == ^blob_id and v.variation_digest in ^Variation.digests(transformations),
        limit: 1
    )
  end

  @doc "The variant, generated (and recorded) if missing."
  def ensure_variant(%Blob{} = blob, transformations) do
    case find_variant(blob.id, transformations) do
      %Blob{} = variant ->
        {:ok, variant}

      nil ->
        with {:ok, rendered} <- render_variant(blob, transformations) do
          case Repo.transaction(fn -> insert_variant!(blob, transformations, rendered) end) do
            {:ok, variant} ->
              {:ok, variant}

            # A concurrent request recorded it first: serve theirs.
            {:error, :exists} ->
              File.rm(path(rendered))
              {:ok, find_variant(blob.id, transformations)}
          end
        end
    end
  end

  @doc "A video's preview image (attached as `preview_image` to the video blob), or `nil`."
  def preview_image(%Blob{id: id}) do
    Replica.one(
      from b in Blob,
        join: a in Attachment,
        on: a.blob_id == b.id,
        where:
          a.record_type == "ActiveStorage::Blob" and a.record_id == ^id and
            a.name == "preview_image",
        limit: 1
    )
  end

  def get_blob(id), do: Replica.get(Blob, id)

  ## Purge

  @doc """
  Deletes a record's attachments named `name`, their blobs, and the blobs' variants (in the
  caller's transaction). Returns the keys of the files to delete once it commits.
  """
  def purge_attachments!(record_type, record_id, name) do
    {_, blob_ids} =
      Repo.delete_all(
        from(a in Attachment,
          where: a.record_type == ^record_type and a.record_id == ^record_id and a.name == ^name,
          select: a.blob_id
        )
      )

    purge_blobs!(blob_ids)
  end

  defp purge_blobs!([]), do: []

  defp purge_blobs!(blob_ids) do
    {_, record_ids} =
      Repo.delete_all(from(v in VariantRecord, where: v.blob_id in ^blob_ids, select: v.id))

    {_, variant_blob_ids} =
      Repo.delete_all(
        from(a in Attachment,
          where: a.record_type == "ActiveStorage::VariantRecord" and a.record_id in ^record_ids,
          select: a.blob_id
        )
      )

    {_, keys} =
      Repo.delete_all(
        from(b in Blob, where: b.id in ^(blob_ids ++ variant_blob_ids), select: b.key)
      )

    keys
  end

  @doc "Removes stored files by key (after the transaction that purged their rows)."
  def delete_files(keys), do: Enum.each(keys, &File.rm(path(&1)))
end
