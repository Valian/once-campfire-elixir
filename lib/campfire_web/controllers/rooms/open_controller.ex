defmodule CampfireWeb.Rooms.OpenController do
  use CampfireWeb, :controller

  import CampfireWeb.Rooms.Access

  alias Campfire.Accounts.User
  alias Campfire.Rooms
  alias CampfireWeb.RoomBroadcasts

  @default_name "New room"

  # Open and closed rooms convert into each other, so both are in reach; directs never are
  # (promoting one would republish its history to the whole account).
  plug :fetch_room, [:open, :closed] when action in [:show, :edit, :update]
  plug :ensure_can_administer when action == :update
  plug :ensure_can_create_rooms when action in [:new, :create]
  plug :assign_last_room when action in [:new, :edit]

  def show(conn, _params), do: redirect(conn, to: "/rooms/#{conn.assigns.room.id}")

  def new(conn, _params) do
    render(conn, :form,
      room: nil,
      name: @default_name,
      can_administer: true,
      users: Rooms.active_users()
    )
  end

  def create(conn, params) do
    room = Rooms.create_open_room(conn.assigns.current_user, room_name(params))
    RoomBroadcasts.room_created(room, [])
    redirect(conn, to: "/rooms/#{room.id}")
  end

  def edit(conn, _params) do
    room = conn.assigns.room

    render(conn, :form,
      room: room,
      name: room.name,
      can_administer: User.can_administer?(conn.assigns.current_user, room),
      users: Rooms.active_users()
    )
  end

  # Submitting here converts a closed room into an open one.
  def update(conn, params) do
    room = conn.assigns.room
    {room, _revoked} = Rooms.update_room(room, :open, room_name(params, room.name))
    RoomBroadcasts.room_updated(room, [])
    redirect(conn, to: "/rooms/#{room.id}")
  end

  defp room_name(params, default \\ @default_name) do
    case params do
      %{"room" => %{"name" => name}} when is_binary(name) -> name
      _ -> default
    end
  end
end
