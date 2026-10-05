defmodule CampfireWeb.UserAuth do
  @moduledoc """
  Authentication by the `session_token` cookie (a signed `sessions.token`), as in Rails.

  Plugs: `fetch_current_user` assigns `@current_user` (or `nil`) and `@current_session`;
  `require_authenticated_user` redirects to sign-in (remembering the URL) and refuses bots.
  The cable endpoint can reuse `fetch_current_user/2` on its upgrade request.
  """
  use CampfireWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias CampfireWeb.Plugs

  @cookie "session_token"
  @cookie_options [
    sign: true,
    max_age: 20 * 365 * 24 * 60 * 60,
    http_only: true,
    same_site: "Lax"
  ]

  def fetch_current_user(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])

    with token when is_binary(token) <- conn.cookies[@cookie],
         {session, user} <- Accounts.get_session_and_user(token) do
      Accounts.resume_session(session, user,
        user_agent: user_agent(conn),
        ip_address: Plugs.remote_ip(conn)
      )

      conn |> assign(:current_session, session) |> assign(:current_user, user)
    else
      _ -> conn |> assign(:current_session, nil) |> assign(:current_user, nil)
    end
  end

  def require_authenticated_user(conn, _opts) do
    case conn.assigns.current_user do
      %User{role: :bot} ->
        conn |> send_resp(403, "") |> halt()

      %User{} ->
        conn

      nil ->
        conn
        |> fetch_session()
        |> maybe_store_return_to()
        |> redirect(to: ~p"/session/new")
        |> halt()
    end
  end

  @doc "Starts a session and redirects to the remembered URL or `/`."
  def log_in_user(conn, %User{} = user) do
    session =
      Accounts.start_session!(user,
        user_agent: user_agent(conn),
        ip_address: Plugs.remote_ip(conn)
      )

    return_to = get_session(conn, :return_to)

    conn
    |> renew_session()
    |> put_resp_cookie(@cookie, session.token, @cookie_options)
    |> redirect(to: return_to || ~p"/")
  end

  def log_out_user(conn) do
    if session = conn.assigns[:current_session], do: Accounts.delete_session(session.token)
    if user = conn.assigns[:current_user], do: disconnect_cable(user)

    conn
    |> renew_session()
    |> delete_resp_cookie(@cookie, http_only: true, same_site: "Lax")
    |> redirect(to: ~p"/")
  end

  @doc """
  Asks the user's open cable connections to disconnect (and reconnect, re-authenticating).
  The cable handler subscribes to this topic.
  """
  def disconnect_cable(%User{id: id}) do
    Phoenix.PubSub.local_broadcast(
      Campfire.PubSub,
      "user_connections:#{id}",
      {:disconnect, reconnect: true}
    )
  end

  # A fresh session (no fixation) that already holds a new CSRF secret: the response to the
  # login POST carries it, so pages rendered later for the same cookie jar verify their tokens
  # without another Set-Cookie (bench/loadgen ignores Set-Cookie after login, SPEC T3).
  defp renew_session(conn) do
    delete_csrf_token()
    conn = conn |> configure_session(renew: true) |> clear_session()
    _ = get_csrf_token()
    conn
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  defp user_agent(conn), do: conn |> get_req_header("user-agent") |> List.first()
end
