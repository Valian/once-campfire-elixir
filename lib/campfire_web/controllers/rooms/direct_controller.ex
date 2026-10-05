defmodule CampfireWeb.Rooms.DirectController do
  use CampfireWeb, :controller

  import CampfireWeb.Rooms.Access

  alias Campfire.Rooms
  alias CampfireWeb.RoomBroadcasts

  # Every member may edit or delete a direct room; nothing else is reachable from here.
  plug :fetch_room, [:direct] when action in [:edit, :delete]
  plug :assign_last_room when action == :edit

  def new(conn, _params), do: render(conn, :new)

  def create(conn, params) do
    {_, room} = Rooms.find_or_create_direct_room(conn.assigns.current_user, user_ids(params))
    # As in Rails, an existing room is announced again (Turbo moves it to the front).
    RoomBroadcasts.room_created(room, Rooms.members(room))
    redirect(conn, to: "/rooms/#{room.id}")
  end

  def edit(conn, _params) do
    room = conn.assigns.room
    members = Rooms.members(room)
    me = conn.assigns.current_user

    shown =
      case members do
        [_, _ | _] -> Enum.reject(members, &(&1.id == me.id))
        members -> members
      end

    render(conn, :edit,
      room: room,
      users: shown,
      display_name: Rooms.display_name(room, members, me)
    )
  end

  def delete(conn, _params) do
    room = conn.assigns.room
    Rooms.destroy_room(room)
    RoomBroadcasts.room_destroyed(room)
    redirect(conn, to: "/")
  end
end
