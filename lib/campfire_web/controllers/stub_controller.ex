defmodule CampfireWeb.StubController do
  @moduledoc """
  Out-of-scope pages the app links to (SPEC §5, §16): account settings, join links, QR codes,
  first run, link unfurling. Each answers without a 500.
  """
  use CampfireWeb, :controller

  @not_found File.read!(Path.expand("../../../priv/static/404.html", __DIR__))
  @external_resource Path.expand("../../../priv/static/404.html", __DIR__)

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, @not_found)
  end

  @doc "`POST /unfurl_link`: nothing to unfurl, so the composer leaves the link as typed."
  def no_content(conn, _params), do: send_resp(conn, 204, "")

  @doc "`/first_run`: the account exists already, as Rails redirects once set up."
  def first_run(conn, _params), do: redirect(conn, to: ~p"/")
end
