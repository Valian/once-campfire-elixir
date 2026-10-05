defmodule Campfire.Avatars do
  @moduledoc """
  User avatars in Active Storage (`User` / `avatar`) and their `square` variant
  (`resize_to_limit: [512, 512], format: :webp`), stored the way Rails stores them so either
  app finds the other's files (SPEC §2.4).
  """
  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Accounts.{SessionCache, User}
  alias Campfire.Schema.Timestamp
  alias Campfire.Storage.{Attachment, Blob, VariantRecord}

  # Base64(SHA1(Marshal.dump({format: :webp, resize_to_limit: [512, 512]}))).
  @square_digest "6gwfjNKv9eUy9jNUtEZvQFLU0hQ="
  @variable_types ~w(image/png image/gif image/jpeg image/tiff image/webp image/avif image/heic image/heif)

  @doc "The avatar blob, if one is attached."
  def avatar_blob(user_id) do
    Replica.one(
      from a in Attachment,
        join: b in assoc(a, :blob),
        where: a.record_type == "User" and a.record_id == ^user_id and a.name == "avatar",
        order_by: [desc: a.id],
        limit: 1,
        select: b
    )
  end

  def attached?(user_id), do: avatar_blob(user_id) != nil

  @doc """
  The path of the avatar's square webp variant, generating it if missing. `nil` when the
  user has no avatar or it isn't an image libvips can process (Rails `avatar_variant`).
  """
  def square_path(user_id) do
    with %Blob{content_type: type} = blob when type in @variable_types <- avatar_blob(user_id) do
      case square_blob(blob.id) do
        %Blob{key: key} -> path(key)
        nil -> generate_square(blob)
      end
    else
      _ -> nil
    end
  end

  defp square_blob(blob_id) do
    Replica.one(
      from v in VariantRecord,
        join: a in Attachment,
        on:
          a.record_type == "ActiveStorage::VariantRecord" and a.record_id == v.id and
            a.name == "image",
        join: b in Blob,
        on: b.id == a.blob_id,
        where: v.blob_id == ^blob_id and v.variation_digest == @square_digest,
        limit: 1,
        select: b
    )
  end

  defp generate_square(%Blob{} = blob) do
    with {:ok, image} <-
           Vix.Vips.Operation.thumbnail(path(blob.key), 512, height: 512, size: :VIPS_SIZE_DOWN),
         {:ok, webp} <- Vix.Vips.Image.write_to_buffer(image, ".webp") do
      filename = Path.rootname(blob.filename) <> ".webp"
      variant = store_blob!(webp, filename, "image/webp", %{"identified" => true})

      Repo.transaction(fn ->
        %{id: record_id} =
          Repo.insert!(%VariantRecord{blob_id: blob.id, variation_digest: @square_digest},
            on_conflict: :nothing
          )

        if record_id do
          Repo.insert!(%Attachment{
            name: "image",
            record_type: "ActiveStorage::VariantRecord",
            record_id: record_id,
            blob_id: variant.id
          })
        end
      end)

      # A concurrent request may have won the race; serve whichever variant is recorded.
      case square_blob(blob.id) do
        %Blob{key: key} -> path(key)
        nil -> nil
      end
    else
      _ -> nil
    end
  end

  @doc """
  Attaches an uploaded image as the user's avatar (replacing any previous one), generates
  the square variant, and bumps the user's `updated_at` (so `?v=` changes).
  """
  def attach(%User{} = user, %Plug.Upload{path: upload, filename: filename, content_type: type}) do
    bytes = File.read!(upload)
    metadata = analyze(upload)

    blob =
      store_blob!(
        bytes,
        sanitize_filename(filename),
        type || "application/octet-stream",
        metadata
      )

    {:ok, old_keys} =
      Repo.transaction(fn ->
        old_keys = detach!(user.id)

        Repo.insert!(%Attachment{
          name: "avatar",
          record_type: "User",
          record_id: user.id,
          blob_id: blob.id
        })

        touch_user!(user.id)
        old_keys
      end)

    delete_files(old_keys)
    _ = square_path(user.id)
    :ok
  end

  @doc "Removes the user's avatar (Rails `avatar.destroy`, which touches the user)."
  def remove(%User{id: user_id}) do
    {:ok, keys} =
      Repo.transaction(fn ->
        keys = detach!(user_id)
        if keys != [], do: touch_user!(user_id)
        keys
      end)

    delete_files(keys)
    :ok
  end

  # Deletes the avatar attachment rows and purges their blobs and variants. Returns the
  # storage keys whose files can go once the transaction commits.
  defp detach!(user_id) do
    {_, blob_ids} =
      Repo.delete_all(
        from(a in Attachment,
          where: a.record_type == "User" and a.record_id == ^user_id and a.name == "avatar",
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

  defp touch_user!(user_id) do
    Repo.update_all(from(u in User, where: u.id == ^user_id),
      set: [updated_at: Timestamp.utc_now()]
    )

    SessionCache.forget_user(user_id)
  end

  ## Storage

  @doc "`{root}/{key[0,2]}/{key[2,4]}/{key}`."
  def path(key) do
    root = Application.fetch_env!(:campfire, :storage_root)
    Path.join([root, binary_part(key, 0, 2), binary_part(key, 2, 2), key])
  end

  defp store_blob!(bytes, filename, content_type, metadata) do
    key = new_key()
    file = path(key)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, bytes)

    Repo.insert!(%Blob{
      key: key,
      filename: filename,
      content_type: content_type,
      metadata: metadata,
      service_name: "local",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes))
    })
  end

  defp delete_files(keys), do: Enum.each(keys, &File.rm(path(&1)))

  defp analyze(file) do
    case Vix.Vips.Image.new_from_file(file) do
      {:ok, image} ->
        %{
          "identified" => true,
          "width" => Vix.Vips.Image.width(image),
          "height" => Vix.Vips.Image.height(image),
          "analyzed" => true
        }

      _ ->
        %{"identified" => true, "analyzed" => true}
    end
  end

  @key_chars ~c"0123456789abcdefghijklmnopqrstuvwxyz"
  defp new_key do
    for <<byte <- :crypto.strong_rand_bytes(28)>>,
      into: "",
      do: <<Enum.at(@key_chars, rem(byte, 36))>>
  end

  # Active Storage's filename sanitizer.
  defp sanitize_filename(name) do
    name
    |> String.replace(~r/^[\x{200E}\x{200F}\x{202A}-\x{202E}]+/u, "")
    |> String.replace(~r{[/\\:;|%$<>?*"\t\r\n]}, "-")
  end
end
