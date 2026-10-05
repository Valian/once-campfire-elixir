defmodule CampfireWeb.RoomBroadcasts do
  @moduledoc """
  Sidebar updates when rooms or memberships change (SPEC §11.4), sent as Turbo stream actions
  through `CampfireWeb.Cable`. Each payload is rendered once and shared by every recipient.
  """
  alias Campfire.Accounts.User
  alias Campfire.Rooms.{Membership, Room}
  alias CampfireWeb.{Cable, SidebarHTML}

  @doc "A new room: open rooms to everyone, closed and direct rooms to each member."
  def room_created(%Room{type: :open} = room, _members) do
    Cable.broadcast(SidebarHTML.rooms_stream(), stream("prepend", "shared_rooms", shared(room)))
  end

  def room_created(%Room{type: :closed} = room, members) do
    payload = stream("prepend", "shared_rooms", shared(room))
    for %User{id: id} <- members, do: Cable.broadcast(SidebarHTML.user_rooms_stream(id), payload)
    :ok
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
      Cable.broadcast(SidebarHTML.user_rooms_stream(id), stream("prepend", "direct_rooms", html))
    end

    :ok
  end

  @doc "A renamed or converted room: replaces its link, everywhere it's shown."
  def room_updated(%Room{type: :open} = room, _member_ids) do
    Cable.broadcast(SidebarHTML.rooms_stream(), stream("replace", list_id(room), shared(room)))
  end

  def room_updated(%Room{type: :closed} = room, member_ids) do
    payload = stream("replace", list_id(room), shared(room))
    for id <- member_ids, do: Cable.broadcast(SidebarHTML.user_rooms_stream(id), payload)
    :ok
  end

  @doc "A destroyed room leaves every sidebar (Rails broadcasts this on `rooms` for all types)."
  def room_destroyed(%Room{} = room) do
    Cable.broadcast(SidebarHTML.rooms_stream(), remove(list_id(room)))
  end

  @doc "Becoming invisible hides a shared room from the member's sidebar; the reverse shows it."
  def involvement_changed(%Membership{room: %Room{type: :direct}}, _previous), do: :ok

  def involvement_changed(%Membership{involvement: :invisible, room: room, user_id: uid}, _) do
    Cable.broadcast(SidebarHTML.user_rooms_stream(uid), remove(list_id(room)))
  end

  def involvement_changed(%Membership{room: room, user_id: uid}, :invisible) do
    Cable.broadcast(
      SidebarHTML.user_rooms_stream(uid),
      stream("prepend", "shared_rooms", shared(room))
    )
  end

  def involvement_changed(_membership, _previous), do: :ok

  defp shared(room), do: render(SidebarHTML.shared_room(%{room: room, unread: false}))

  defp list_id(room), do: "list_#{Room.param_key(room)}_#{room.id}"

  defp render(rendered), do: Phoenix.HTML.Safe.to_iodata(rendered)

  defp stream(action, target, html) do
    [
      ~s(<turbo-stream action="),
      action,
      ~s(" target="),
      target,
      ~s("><template>),
      html,
      "</template></turbo-stream>"
    ]
    |> IO.iodata_to_binary()
  end

  defp remove(target),
    do: ~s(<turbo-stream action="remove" target="#{target}"></turbo-stream>)
end
