defmodule CampfireWeb.Plugs do
  @moduledoc "Small request plugs shared by the browser pipeline."
  import Plug.Conn

  alias Campfire.Accounts

  @doc """
  Rails forms post the CSRF token as `authenticity_token`; Plug.CSRFProtection reads
  `_csrf_token` (or the `x-csrf-token` header, which Turbo sends). Either valid one passes.
  """
  def accept_authenticity_token(
        %{body_params: %{"authenticity_token" => token} = params} = conn,
        _
      )
      when not is_map_key(params, "_csrf_token") do
    %{conn | body_params: Map.put(params, "_csrf_token", token)}
  end

  def accept_authenticity_token(conn, _), do: conn

  def put_version_headers(conn, _) do
    merge_resp_headers(conn, [
      {"x-version", Application.fetch_env!(:campfire, :app_version)},
      {"x-rev", Application.fetch_env!(:campfire, :git_revision)}
    ])
  end

  @doc "Requests that change state from a banned IP get an empty 429, as in Rails."
  def block_banned_ip(%{method: method} = conn, _) when method in ~w(GET HEAD), do: conn

  def block_banned_ip(conn, _) do
    if Accounts.banned_ip?(remote_ip(conn)) do
      conn |> send_resp(429, "") |> halt()
    else
      conn
    end
  end

  @doc "`@turbo_frame`: the requesting frame's id; pages render the frame layout when set."
  def assign_turbo_frame(conn, _) do
    assign(conn, :turbo_frame, conn |> get_req_header("turbo-frame") |> List.first())
  end

  def remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
