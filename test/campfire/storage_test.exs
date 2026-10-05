defmodule Campfire.StorageTest do
  @moduledoc "Against vectors Rails generated with the bench secret (once-campfire-rust `vectors/storage.json`)."
  use Campfire.DataCase, async: true

  alias Campfire.Storage
  alias Campfire.Storage.{Blob, Files, Variation}

  @vectors "test/fixtures/storage_vectors.json" |> File.read!() |> Jason.decode!()

  defp typed(%{"hash" => pairs}) do
    Enum.map(pairs, fn [k, v] -> {String.to_atom(k), typed(v)} end)
  end

  defp typed(%{"sym" => s}), do: {:sym, s}
  defp typed(%{"str" => s}), do: s
  defp typed(v), do: v

  test "variation digests and keys" do
    for v <- @vectors["variations"],
        transformations = typed(v["typed"]),
        Enum.all?(transformations, fn {k, _} -> k in [:format, :resize_to_limit] end),
        Enum.all?(
          List.wrap(transformations[:resize_to_limit]),
          &(is_integer(&1) and &1 in 0..1_073_741_823)
        ) do
      assert Variation.marshal(transformations) |> Base.encode16(case: :lower) == v["marshal_hex"],
             v["inspect"]

      assert Variation.digest(transformations) == v["digest"], v["inspect"]
      assert Variation.key(transformations) == v["key"], v["inspect"]
      assert {:ok, decoded} = Variation.decode_key(v["key"])
      assert Variation.digest(decoded) == v["decoded_digest"]
    end
  end

  test "filenames: sanitizing, dispositions, paths" do
    for f <- @vectors["filenames"] do
      input = Base.decode16!(f["input_hex"], case: :lower)
      sanitized = Files.sanitize(input)
      assert sanitized == f["sanitized"]
      assert Files.content_disposition("inline", sanitized) == f["inline"]
      assert Files.escape_path(sanitized) == f["escaped_path"]
    end
  end

  test "blob and representation paths" do
    for m <- @vectors["messages"], blob = struct(Blob, atomize(m["blob"])) do
      assert Storage.blob_path(blob) == m["rails_blob_path"]
      assert Storage.blob_path(blob, disposition: "attachment") == m["rails_blob_download_path"]

      if m["thumb_path"] && Storage.variable?(blob),
        do: assert(Storage.representation_path(blob, Storage.thumb(blob)) == m["thumb_path"])
    end
  end

  test "content types" do
    fixtures = "/Users/jakub/Projects/once-campfire-elixir/bench/black_hole.jpg"

    for c <- @vectors["marcel"], c["data_hex"] do
      path = Path.join(System.tmp_dir!(), "marcel-#{System.unique_integer([:positive])}")
      File.write!(path, Base.decode16!(c["data_hex"], case: :lower))

      assert Files.content_type(path, c["name"], c["declared_type"]) == c["content_type"],
             inspect(c)

      File.rm!(path)
    end

    if File.exists?(fixtures),
      do: assert(Files.content_type(fixtures, "renamed.txt", nil) == "image/jpeg")
  end

  test "seed variants are found under Rails' digests" do
    # black_hole.jpg (blob 7) has its thumb (blob 8); the video (9) has a preview image (10)
    # whose poster was stored with a symbol format.
    assert %Blob{id: 8} = Storage.find_variant(7, Storage.thumb(Storage.get_blob(7)))
    assert %Blob{id: 10} = Storage.preview_image(Storage.get_blob(9))
    {:ok, from_url} = Variation.decode_key(Variation.key(Storage.poster()))
    assert %Blob{id: 12} = Storage.find_variant(10, from_url)
  end

  test "rendering a variant" do
    source = Storage.get_blob(7)
    assert {:ok, %Blob{} = variant} = Storage.render_variant(source, Storage.thumb(source))
    assert variant.filename == "black_hole.jpg"
    assert variant.content_type == "image/jpeg"
    assert {:ok, 1200, 675} = Files.image_dimensions(Storage.path(variant))
    File.rm!(Storage.path(variant))
  end

  defp atomize(map),
    do:
      Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.take(~w(id key filename content_type byte_size checksum)a)
end
