defmodule CampfireWeb.ConnCase do
  @moduledoc "Request tests against the seed database."
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint CampfireWeb.Endpoint

      use CampfireWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Campfire.DataCase, only: [label: 1]
      import CampfireWeb.ConnCase
    end
  end

  setup tags do
    Campfire.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A conn with CSRF protection on (Phoenix.ConnTest skips it by default)."
  def csrf_conn,
    do: Phoenix.ConnTest.build_conn() |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)

  @doc "`name=value` of every Set-Cookie in `conn`, as a map."
  def set_cookies(conn) do
    for header <- Plug.Conn.get_resp_header(conn, "set-cookie"), into: %{} do
      [pair | _] = String.split(header, ";")
      [name, value] = String.split(pair, "=", parts: 2)
      {name, value}
    end
  end

  def cookie_header(jar), do: Enum.map_join(jar, "; ", fn {k, v} -> "#{k}=#{v}" end)

  @doc "The token the loadgen scrapes: `<meta name=\"csrf-token\" content=\"…\"`."
  def csrf_meta(html) do
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]*)"/, html)
    token
  end
end
