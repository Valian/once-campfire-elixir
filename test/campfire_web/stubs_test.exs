defmodule CampfireWeb.StubsTest do
  use CampfireWeb.ConnCase

  test "account logo: the stock icon, public and cacheable, no sign-in", %{conn: conn} do
    conn = get(conn, "/account/logo")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]

    assert get_resp_header(conn, "cache-control") == [
             "max-age=300, public, stale-while-revalidate=604800"
           ]

    small = get(build_conn(), "/account/logo?size=small")
    assert byte_size(small.resp_body) < byte_size(conn.resp_body)
  end

  test "out-of-scope links answer without a 500", %{conn: conn} do
    conn = sign_in(conn, label("users.david"))

    assert get(conn, "/account/edit").status == 404
    assert get(recycle(conn), "/rooms/#{label("rooms.hq")}/settings").status == 404
    assert get(recycle(conn), "/join/abc").status == 404
    assert get(recycle(conn), "/qr_code/abc").status == 404
    assert redirected_to(get(recycle(conn), "/first_run")) == "/"
    assert post(recycle(conn), "/unfurl_link", %{"url" => "https://example.com"}).status == 204
  end
end
