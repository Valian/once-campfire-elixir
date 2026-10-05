defmodule CampfireWeb.AssetCacheTest do
  use CampfireWeb.ConnCase, async: true

  @css "/assets/_reset-9c3efd7b.css"
  @disk Application.app_dir(:campfire, "priv/static/assets/_reset-9c3efd7b.css")

  test "serves stylesheets and scripts from memory, gzipped when accepted", %{conn: conn} do
    plain = get(conn, @css)
    assert plain.status == 200
    assert plain.resp_body == File.read!(@disk)
    assert get_resp_header(plain, "content-type") == ["text/css"]
    assert get_resp_header(plain, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(plain, "vary") == ["Accept-Encoding"]
    assert get_resp_header(plain, "content-encoding") == []

    gz = build_conn() |> put_req_header("accept-encoding", "gzip, deflate") |> get(@css)
    assert get_resp_header(gz, "content-encoding") == ["gzip"]
    assert :zlib.gunzip(gz.resp_body) == plain.resp_body

    [etag] = get_resp_header(plain, "etag")
    assert build_conn() |> put_req_header("if-none-match", etag) |> get(@css) |> response(304)
  end

  test "leaves other assets to Plug.Static", %{conn: conn} do
    svg = CampfireWeb.Assets.path("add.svg")
    conn = get(conn, svg)
    assert conn.status == 200
    assert conn.state == :file
    assert get(build_conn(), "/assets/nope-123.css").status == 404
  end
end
