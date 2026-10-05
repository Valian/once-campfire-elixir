defmodule CampfireWeb.GzipTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  @body String.duplicate("<p>hello campfire</p>\n", 200)

  defp respond(accept, fun \\ & &1, status \\ 200, body \\ @body) do
    conn(:get, "/")
    |> then(&if(accept, do: put_req_header(&1, "accept-encoding", accept), else: &1))
    |> CampfireWeb.Gzip.call(CampfireWeb.Gzip.init(level: 3))
    |> fun.()
    |> send_resp(status, body)
  end

  defp encoding(conn), do: get_resp_header(conn, "content-encoding")

  test "gzips when the client accepts gzip" do
    conn = respond("gzip")
    assert encoding(conn) == ["gzip"]
    assert :zlib.gunzip(conn.resp_body) == @body
    assert byte_size(conn.resp_body) < byte_size(@body)

    assert encoding(respond("gzip, deflate, br")) == ["gzip"]
  end

  test "leaves the body alone otherwise" do
    for accept <- [nil, "identity", "deflate", "gzip, deflate, br, zstd"] do
      conn = respond(accept)
      assert encoding(conn) == [], inspect(accept)
      assert conn.resp_body == @body
    end

    assert encoding(respond("gzip", & &1, 304, "")) == []
    assert encoding(respond("gzip", & &1, 200, "")) == []
    assert encoding(respond("gzip", &put_resp_header(&1, "etag", ~s("abc")))) == []
    assert encoding(respond("gzip", &put_resp_header(&1, "etag", ~s(W/"abc")))) == ["gzip"]
    assert encoding(respond("gzip", &put_resp_header(&1, "cache-control", "no-transform"))) == []
    assert encoding(respond("gzip", &put_resp_header(&1, "content-encoding", "br"))) == ["br"]
  end
end
