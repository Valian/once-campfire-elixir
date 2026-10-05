defmodule CampfireWeb.WelcomeController do
  use CampfireWeb, :controller

  alias Campfire.Rooms

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Rooms.last_visited_room(user.id, last_room_cookie(conn)) do
      nil -> render(conn, :show)
      room -> redirect(conn, to: "/rooms/#{room.id}")
    end
  end

  # Rails' permanent `last_room` cookie, set by the room page.
  defp last_room_cookie(conn) do
    with value when is_binary(value) <- fetch_cookies(conn).cookies["last_room"],
         {id, ""} <- Integer.parse(value) do
      id
    else
      _ -> nil
    end
  end
end
