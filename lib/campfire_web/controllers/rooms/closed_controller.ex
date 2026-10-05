defmodule CampfireWeb.Rooms.ClosedController do
  use CampfireWeb, :controller

  import CampfireWeb.Rooms.Access

  alias Campfire.Accounts.User
  alias Campfire.Rooms
  alias CampfireWeb.{RoomBroadcasts, UserAuth}

  @default_name "New room"

  # Open and closed rooms convert into each other; directs are out of reach (converting one
  # would let its creator revise who's in it).
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
      selected_users: [],
      unselected_users: Rooms.active_users()
    )
  end

  def create(conn, params) do
    room =
      Rooms.create_closed_room(conn.assigns.current_user, room_name(params), user_ids(params))

    RoomBroadcasts.room_created(room, Rooms.members(room))
    redirect(conn, to: "/rooms/#{room.id}")
  end

  def edit(conn, _params) do
    room = conn.assigns.room
    member_ids = MapSet.new(Rooms.member_ids(room))
    {selected, unselected} = Enum.split_with(Rooms.active_users(), &(&1.id in member_ids))

    render(conn, :form,
      room: room,
      name: room.name,
      can_administer: User.can_administer?(conn.assigns.current_user, room),
      selected_users: selected,
      unselected_users: unselected
    )
  end

  # Grants the checked users, revokes the rest (their cable connections are reset so they
  # stop receiving the room); submitting here converts an open room into a closed one.
  def update(conn, params) do
    room = conn.assigns.room

    {room, revoked} =
      Rooms.update_room(room, :closed, room_name(params, room.name), user_ids(params))

    for user_id <- revoked, do: UserAuth.disconnect_cable(%User{id: user_id})
    RoomBroadcasts.room_updated(room, Rooms.member_ids(room))
    redirect(conn, to: "/rooms/#{room.id}")
  end

  defp room_name(params, default \\ @default_name) do
    case params do
      %{"room" => %{"name" => name}} when is_binary(name) -> name
      _ -> default
    end
  end
end
