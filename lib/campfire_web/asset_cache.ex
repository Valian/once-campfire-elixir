defmodule CampfireWeb.AssetCache do
  @moduledoc """
  Serves the digested stylesheets and scripts under `/assets` from memory.

  Every page loads them, and they never change (the digest is in the name), yet `Plug.Static`
  stats the file and its `.gz` sibling and opens and sendfiles it on every request: ~3× the CPU
  of a response from memory (bench/PERF.md). Thruster, in front of the Rails app, caches them
  in memory too.

  At boot, `load/0` reads each `.css`/`.js` (~4 MB with their `.gz` siblings) into
  `:persistent_term`. Responses carry the same headers as `Plug.Static`'s (immutable
  cache-control, a strong ETag, the `.gz` body when gzip is accepted), minus range support,
  which browsers don't use for these. Anything else (images, sounds, unknown paths) falls
  through to `Plug.Static`.
  """
  @behaviour Plug

  import Plug.Conn

  @root "priv/static/assets"
  @cache_control "public, max-age=31536000, immutable"

  @doc "Reads the assets into `:persistent_term` (once, at boot)."
  def load do
    root = Application.app_dir(:campfire, @root)

    for path <- Path.wildcard(Path.join(root, "**/*.{css,js}")), File.regular?(path) do
      body = File.read!(path)

      gzip =
        case File.read(path <> ".gz") do
          {:ok, gzip} -> gzip
          {:error, _} -> nil
        end

      asset = %{
        body: body,
        gzip: gzip,
        type: MIME.from_path(path),
        etag: ~s("#{Integer.to_string(:erlang.phash2(body), 16)}")
      }

      :persistent_term.put({__MODULE__, Path.relative_to(path, root)}, asset)
    end

    :ok
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: ["assets" | segments]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    case :persistent_term.get({__MODULE__, Path.join(segments)}, nil) do
      nil -> conn
      asset -> conn |> serve(asset) |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp serve(conn, asset) do
    conn =
      conn
      |> put_resp_header("vary", "Accept-Encoding")
      |> put_resp_header("cache-control", @cache_control)
      |> put_resp_header("etag", asset.etag)

    cond do
      asset.etag in get_req_header(conn, "if-none-match") ->
        send_resp(conn, 304, "")

      asset.gzip && gzip?(conn) ->
        conn
        |> put_resp_header("content-type", asset.type)
        |> put_resp_header("content-encoding", "gzip")
        |> send_resp(200, asset.gzip)

      true ->
        conn
        |> put_resp_header("content-type", asset.type)
        |> send_resp(200, asset.body)
    end
  end

  # As Plug.Static decides whether to serve the `.gz` sibling.
  defp gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.any?(&String.contains?(&1, ["gzip", "*"]))
  end
end
