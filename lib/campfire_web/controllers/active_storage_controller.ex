defmodule CampfireWeb.ActiveStorageController do
  @moduledoc """
  Files at the URLs Rails generates (SPEC §10.2): `blobs/redirect/:signed_id/*filename` and
  `representations/redirect/:signed_blob_id/:variation_key/*filename` (and their `proxy` and
  bare spellings).

  Rails answers these with a redirect to a short-lived disk URL; we serve the bytes directly
  (one round trip fewer, an accepted shortcut). The URLs are signed, public bearer URLs as in
  Rails, and what they name never changes, so responses are cacheable for good. Files go out
  with `sendfile` (not compressed: images are already). Single `Range`s are honoured (video).
  """
  use CampfireWeb, :controller

  alias Campfire.Storage
  alias Campfire.Storage.{Blob, Files, Variation}

  @cache_control "public, max-age=31536000, immutable"

  def blob(conn, %{"signed_id" => signed_id} = params) do
    with {:ok, id} <- Storage.verify_blob_id(signed_id),
         %Blob{} = blob <- Storage.get_blob(id) do
      serve(conn, blob, params["disposition"])
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def representation(conn, %{"signed_blob_id" => signed_id, "variation_key" => key} = params) do
    with {:ok, id} <- Storage.verify_blob_id(signed_id),
         {:ok, transformations} <- Variation.decode_key(key),
         %Blob{} = blob <- Storage.get_blob(id),
         {:ok, source} <- representable(blob),
         {:ok, variant} <- Storage.ensure_variant(source, transformations) do
      serve(conn, variant, params["disposition"])
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # A video is represented by its preview image (generated when it was posted).
  defp representable(blob) do
    cond do
      Storage.video?(blob) ->
        case Storage.preview_image(blob) do
          nil -> :error
          image -> {:ok, image}
        end

      Storage.variable?(blob) ->
        {:ok, blob}

      true ->
        :error
    end
  end

  defp serve(conn, %Blob{} = blob, disposition) do
    path = Storage.path(blob)

    case File.stat(path) do
      {:ok, %{size: size, type: :regular}} ->
        disposition =
          if disposition == "attachment" or not Files.inline?(blob.content_type),
            do: "attachment",
            else: "inline"

        conn
        |> put_resp_header("content-type", Files.serve_as(blob.content_type))
        |> put_resp_header(
          "content-disposition",
          Files.content_disposition(disposition, blob.filename)
        )
        |> put_resp_header("cache-control", @cache_control)
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_range(path, size)

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp send_range(conn, path, size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> spec] ->
        case parse_range(spec, size) do
          {first, last} ->
            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> send_file(206, path, first, last - first + 1)

          :unsatisfiable ->
            conn |> put_resp_header("content-range", "bytes */#{size}") |> send_resp(416, "")

          :ignore ->
            send_file(conn, 200, path)
        end

      _ ->
        send_file(conn, 200, path)
    end
  end

  defp parse_range(spec, size) do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] ->
        with {n, ""} when n > 0 <- Integer.parse(suffix),
             do: {max(size - n, 0), size - 1},
             else: (_ -> :ignore)

      [first, ""] ->
        case Integer.parse(first) do
          {f, ""} when f < size -> {f, size - 1}
          {_, ""} -> :unsatisfiable
          _ -> :ignore
        end

      [first, last] ->
        with {f, ""} <- Integer.parse(first),
             {l, ""} when l >= f <- Integer.parse(last) do
          if f < size, do: {f, min(l, size - 1)}, else: :unsatisfiable
        else
          _ -> :ignore
        end

      _ ->
        :ignore
    end
  end
end
