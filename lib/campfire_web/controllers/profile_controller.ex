defmodule CampfireWeb.ProfileController do
  use CampfireWeb, :controller

  alias Campfire.{Accounts, Avatars, Rooms}
  alias CampfireWeb.{AvatarCache, Platform, UserComponents}

  def show(conn, _params) do
    user = conn.assigns.current_user
    {directs, shared, members} = Rooms.memberships_with_rooms(user.id)

    render(conn, :show,
      user: user,
      shared_memberships: shared,
      direct_memberships: directs,
      direct_members: members,
      avatar?: Avatars.attached?(user.id),
      platform: Platform.from_conn(conn),
      back_url: UserComponents.back_url(conn),
      base_url: CampfireWeb.Plugs.base_url(conn)
    )
  end

  def update(conn, %{"user" => params}) when is_map(params) do
    user = conn.assigns.current_user

    result =
      case params do
        %{"avatar" => %Plug.Upload{} = upload} -> Avatars.attach(user, upload)
        _ -> :ok
      end

    notice =
      with :ok <- result,
           {:ok, _} <- Accounts.update_profile(user, Map.delete(params, "avatar")) do
        if params["avatar"],
          do: "It may take up to 30 minutes to change everywhere.",
          else: "✓"
      else
        _ -> nil
      end

    AvatarCache.forget(user.id)

    conn
    |> put_flash(
      if(notice, do: :notice, else: :alert),
      notice || "That email address is already taken."
    )
    |> redirect(to: ~p"/users/me/profile")
  end

  def update(conn, _params), do: redirect(conn, to: ~p"/users/me/profile")
end
