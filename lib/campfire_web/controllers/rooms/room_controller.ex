defmodule CampfireWeb.Rooms.RoomController do
  @moduledoc """
  `GET /rooms` and `DELETE /rooms/:id`. (The room page itself, `GET /rooms/:id`, lives with
  the messages.)
  """
  use CampfireWeb, :controller

  import CampfireWeb.Rooms.Access

  alias Campfire.Rooms
  alias CampfireWeb.RoomBroadcasts

  plug :fetch_room, [:open, :closed, :direct] when action == :delete
  plug :ensure_can_administer when action == :delete

  def index(conn, _params) do
    case Rooms.latest_room(conn.assigns.current_user.id) do
      nil -> redirect(conn, to: "/")
      room -> redirect(conn, to: "/rooms/#{room.id}")
    end
  end

  def delete(conn, _params) do
    room = conn.assigns.room
    Rooms.destroy_room(room)
    RoomBroadcasts.room_destroyed(room)
    redirect(conn, to: "/")
  end
end
