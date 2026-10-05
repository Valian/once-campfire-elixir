defmodule CampfireWeb.WelcomeController do
  use CampfireWeb, :controller

  alias Campfire.Rooms

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Rooms.last_visited_room(user.id, CampfireWeb.Plugs.last_room_id(conn)) do
      nil -> render(conn, :show)
      room -> redirect(conn, to: "/rooms/#{room.id}")
    end
  end
end
