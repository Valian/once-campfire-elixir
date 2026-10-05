defmodule CampfireWeb.UserController do
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias CampfireWeb.{AvatarCache, UserComponents}

  plug :fetch_user when action in [:show, :ban, :unban]
  plug :ensure_administrator when action in [:ban, :unban]

  def show(conn, _params) do
    render(conn, :show,
      user: conn.assigns.user,
      back_url: UserComponents.back_url(conn),
      base_url: CampfireWeb.Plugs.base_url(conn)
    )
  end

  @doc """
  `POST /users/:user_id/ban`: bans the user's session IPs, signs them out everywhere and
  marks them banned. (Rails also deletes their messages in a background job; not done here.)
  """
  def ban(conn, _params) do
    user = conn.assigns.user
    :ok = Accounts.ban_user(user)
    CampfireWeb.UserAuth.disconnect_cable(user)
    AvatarCache.forget(user.id)
    redirect(conn, to: ~p"/users/#{user.id}")
  end

  def unban(conn, _params) do
    user = conn.assigns.user
    :ok = Accounts.unban_user(user)
    AvatarCache.forget(user.id)
    redirect(conn, to: ~p"/users/#{user.id}")
  end

  defp fetch_user(conn, _) do
    case Accounts.get_user(conn.params["id"] || conn.params["user_id"]) do
      nil -> conn |> send_resp(404, "") |> halt()
      user -> assign(conn, :user, user)
    end
  end

  defp ensure_administrator(conn, _) do
    if Accounts.User.administrator?(conn.assigns.current_user) do
      conn
    else
      conn |> send_resp(403, "") |> halt()
    end
  end
end
