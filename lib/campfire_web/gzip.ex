defmodule CampfireWeb.Gzip do
  @moduledoc """
  Gzips response bodies at a chosen zlib level.

  Bandit would gzip them anyway, but with `:zlib.gzip/1`, fixed at zlib's default level 6, which
  costs more CPU than rendering the room page itself (~2.7 ms vs ~1.5 ms for its 460 KB). Level 3
  is ~3× cheaper for ~30% more bytes (bench/PERF.md). Bandit leaves responses that already have a
  `content-encoding` alone and still adds `vary: accept-encoding`.

  Bandit 1.12's `deflate_options` only apply to the `deflate` encoding; a `level` option for
  gzip upstream would make this module unnecessary. Otherwise the same rules as Bandit: never
  for 204/304, empty bodies, `cache-control: no-transform`, strong ETags or bodies already
  encoded. Files (`send_file`) and chunked responses are left to Bandit.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: Keyword.get(opts, :level, 3)

  @impl true
  def call(conn, level) do
    if accepts_gzip?(conn),
      do: register_before_send(conn, &compress(&1, level)),
      else: conn
  end

  defp compress(%Plug.Conn{state: :set, status: status, resp_body: body} = conn, level)
       when status not in [204, 304] do
    if body != "" and body != [] and transformable?(conn) do
      %{conn | resp_body: gzip(body, level)}
      |> put_resp_header("content-encoding", "gzip")
    else
      conn
    end
  end

  defp compress(conn, _level), do: conn

  defp transformable?(conn) do
    get_resp_header(conn, "content-encoding") == [] and
      not Enum.any?(get_resp_header(conn, "cache-control"), &(&1 =~ "no-transform")) and
      Enum.all?(get_resp_header(conn, "etag"), &String.starts_with?(&1, "W/"))
  end

  # Bandit (1.12) prefers zstd when the client offers it, as browsers do; leave those to it.
  defp accepts_gzip?(conn) do
    accept = conn |> get_req_header("accept-encoding") |> Enum.join(",")
    String.contains?(accept, "gzip") and not String.contains?(accept, "zstd")
  end

  # windowBits 31 = 15 + 16: a gzip header and trailer around raw deflate, as `:zlib.gzip/1`.
  defp gzip(body, level) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, level, :deflated, 31, 8, :default)
      data = :zlib.deflate(z, body, :finish)
      :ok = :zlib.deflateEnd(z)
      data
    after
      :zlib.close(z)
    end
  end
end
