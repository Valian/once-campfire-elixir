defmodule CampfireWeb.Cable.Upgrade do
  @moduledoc """
  `GET /cable`: the WebSocket upgrade (SPEC §11.1), mounted in the endpoint before the
  parsers and the session (it needs neither).

    * `Origin` must be the request's own host, `http(s)://{Host}` (Rails'
      `allow_same_origin_as_host`); otherwise, or without an upgrade, 404 as Rails.
    * `actioncable-v1-json` is echoed in `sec-websocket-protocol` when offered (T4).
    * The user comes from the `session_token` cookie, without the HTTP side's activity
      refresh. An unknown or missing session still upgrades: the socket then sends
      `disconnect` (`unauthorized`, no reconnect) and closes, as Rails does.
  """
  @behaviour Plug

  import Plug.Conn

  alias Campfire.Accounts

  @protocol "actioncable-v1-json"
  @websocket_opts [timeout: :infinity, compress: true, max_frame_size: 1_048_576]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["cable"]} = conn, _opts) do
    with true <- conn.method == "GET" and same_origin?(conn),
         :ok <- WebSockAdapter.UpgradeValidation.validate_upgrade(conn) do
      conn
      |> negotiate_protocol()
      |> WebSockAdapter.upgrade(
        CampfireWeb.Cable.Socket,
        %{user: current_user(conn)},
        [early_validate_upgrade: false] ++ @websocket_opts
      )
      |> halt()
    else
      _ -> conn |> send_resp(404, "Page not found") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp same_origin?(conn) do
    with [origin] <- get_req_header(conn, "origin"),
         [host] <- get_req_header(conn, "host") do
      origin == "http://" <> host or origin == "https://" <> host
    else
      _ -> false
    end
  end

  defp negotiate_protocol(conn) do
    offered =
      conn
      |> get_req_header("sec-websocket-protocol")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)

    if @protocol in offered,
      do: put_resp_header(conn, "sec-websocket-protocol", @protocol),
      else: conn
  end

  defp current_user(conn) do
    conn = fetch_cookies(conn, signed: ["session_token"])

    with token when is_binary(token) <- conn.cookies["session_token"],
         {_session, user} <- Accounts.get_session_and_user(token) do
      %{id: user.id, name: user.name}
    else
      _ -> nil
    end
  end
end
