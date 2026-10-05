defmodule CampfireWeb.RoomBroadcasts do
  @moduledoc """
  Sidebar updates when rooms or memberships change (SPEC §11.4), sent as Turbo stream actions
  through `CampfireWeb.Cable`. Each payload is rendered once and shared by every recipient.
  """
  alias Campfire.Accounts.User
  alias Campfire.Rooms.{Membership, Room}
  alias CampfireWeb.{Cable, RoomHTML, SidebarHTML, TurboStream}

  @doc "A new room: open rooms to everyone, closed and direct rooms to each member."
  def room_created(%Room{type: :open} = room, _members),
    do: Cable.broadcast(Cable.rooms_stream(), TurboStream.prepend("shared_rooms", shared(room)))

  def room_created(%Room{type: :closed} = room, members) do
    members
    |> Enum.map(&Cable.user_rooms_stream(&1.id))
    |> Cable.broadcast_many(TurboStream.prepend("shared_rooms", shared(room)))
  end

  # Each member sees the others' avatars and names, so the link is rendered per member.
  def room_created(%Room{type: :direct} = room, members) do
    for %User{id: id} = member <- members do
      others =
        case Enum.reject(members, &(&1.id == id)) do
          [] -> [member]
          others -> others
        end

      html = render(SidebarHTML.direct_room(%{room: room, members: others, unread: false}))
      Cable.broadcast(Cable.user_rooms_stream(id), TurboStream.prepend("direct_rooms", html))
    end

    :ok
  end

  @doc "A renamed or converted room: replaces its link, everywhere it's shown."
  def room_updated(%Room{type: :open} = room, _member_ids),
    do: Cable.broadcast(Cable.rooms_stream(), TurboStream.replace(list_id(room), shared(room)))

  def room_updated(%Room{type: :closed} = room, member_ids) do
    member_ids
    |> Enum.map(&Cable.user_rooms_stream/1)
    |> Cable.broadcast_many(TurboStream.replace(list_id(room), shared(room)))
  end

  @doc "A destroyed room leaves every sidebar (Rails broadcasts this on `rooms` for all types)."
  def room_destroyed(%Room{} = room),
    do: Cable.broadcast(Cable.rooms_stream(), TurboStream.remove(list_id(room)))

  @doc "Becoming invisible hides a shared room from the member's sidebar; the reverse shows it."
  def involvement_changed(%Membership{room: %Room{type: :direct}}, _previous), do: :ok

  def involvement_changed(%Membership{involvement: :invisible, room: room, user_id: uid}, _),
    do: Cable.broadcast(Cable.user_rooms_stream(uid), TurboStream.remove(list_id(room)))

  def involvement_changed(%Membership{room: room, user_id: uid}, :invisible),
    do:
      Cable.broadcast(
        Cable.user_rooms_stream(uid),
        TurboStream.prepend("shared_rooms", shared(room))
      )

  def involvement_changed(_membership, _previous), do: :ok

  defp shared(room), do: render(SidebarHTML.shared_room(%{room: room, unread: false}))

  defp list_id(room), do: RoomHTML.dom_id(room, "list")

  defp render(rendered), do: Phoenix.HTML.Safe.to_iodata(rendered)
end
