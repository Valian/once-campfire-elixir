defmodule CampfireWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :campfire

  # Holds the CSRF secret, flash and return-to URL. Authentication is the separate
  # `session_token` cookie (CampfireWeb.UserAuth).
  @session_options [
    store: :cookie,
    key: "_campfire_session",
    signing_salt: "x7Vw1qMd",
    same_site: "Lax",
    http_only: true
  ]

  def session_options, do: @session_options

  # Health check: before statics, sessions and the router, no DB.
  plug :up

  # Rails' digested assets (bin/extract-assets). Digests make them immutable.
  plug Plug.Static,
    at: "/assets",
    from: {:campfire, "priv/static/assets"},
    gzip: true,
    cache_control_for_etags: "public, max-age=31536000, immutable"

  plug Plug.Static, at: "/", from: :campfire, only: ~w(robots.txt)

  # Action Cable (WebSocket upgrade); needs no parsers or session.
  plug CampfireWeb.Cable.Upgrade

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CampfireWeb.Router

  @up ~s(<!DOCTYPE html><html><body style="background-color: green"></body></html>)

  defp up(%Plug.Conn{path_info: ["up"]} = conn, _opts) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, @up)
    |> halt()
  end

  defp up(conn, _opts), do: conn
end
