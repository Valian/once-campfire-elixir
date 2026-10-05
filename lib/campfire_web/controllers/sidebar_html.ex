defmodule CampfireWeb.SidebarHTML do
  @moduledoc """
  The sidebar (`users/sidebars/show`) and its room links. `shared_room/1` and `direct_room/1`
  are also the payloads `CampfireWeb.RoomBroadcasts` sends when rooms change.
  """
  use CampfireWeb, :html

  alias Campfire.Accounts.{Account, User}
  alias Campfire.Rooms.Room

  embed_templates "sidebar_html/*"

  @doc "A link to an open or closed room (`users/sidebars/rooms/_shared`)."
  attr :room, Room, required: true
  attr :unread, :boolean, default: false

  def shared_room(assigns) do
    ~H"""
    <a
      id={"list_#{Room.param_key(@room)}_#{@room.id}"}
      data-rooms-list-target="room"
      data-room-id={@room.id}
      data-badge-dot-target="unread"
      data-sorted-list-target="item"
      data-sorted-list-name={@room.name}
      style="--column-gap: 0.5em"
      class={["align-center gap room btn txt-nowrap", @unread && "unread"]}
      href={"/rooms/#{@room.id}"}
    >
      <span class="overflow-ellipsis">{@room.name}</span>
    </a>
    """
  end

  @doc """
  A link to a direct room (`users/sidebars/rooms/_direct`); `members` are the members other
  than the viewer (or the viewer alone).
  """
  attr :room, Room, required: true
  attr :members, :list, required: true
  attr :unread, :boolean, default: false

  def direct_room(assigns) do
    ~H"""
    <a
      class={["direct", @unread && "unread"]}
      id={"list_rooms_direct_#{@room.id}"}
      data-rooms-list-target="room"
      data-room-id={@room.id}
      data-badge-dot-target="unread"
      data-sorted-list-target="item"
      data-sorted-list-number={epoch_ms(@room.updated_at)}
      href={"/rooms/#{@room.id}"}
    >
      <%= case @members do %>
        <% [member] -> %>
          <span class="avatar">
            <img aria-hidden="true" src={avatar_path(member)} width="48" height="48" />
          </span>
        <% members -> %>
          <div class="avatar__group">
            <span :for={member <- Enum.take(members, 4)} class="avatar">
              <img aria-hidden="true" src={avatar_path(member)} width="20" height="20" />
            </span>
          </div>
      <% end %>

      <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
        <span class="txt-nowrap overflow-ellipsis">
          <span class="for-screen-reader">Ping with</span>
          {direct_label(@members)}
        </span>
      </span>
    </a>
    """
  end

  # One member: their first name. Several: each one's initials (first ≤3 words), "A+B" or
  # "A, B, and C".
  defp direct_label([member]), do: first_word(member.name)

  defp direct_label(members) do
    members
    |> Enum.map(fn %User{name: name} ->
      name
      |> String.split()
      |> Enum.take(3)
      |> Enum.map_join(&(&1 |> String.first() |> String.upcase()))
    end)
    |> Campfire.Rooms.to_sentence("+")
  end

  defp first_word(name), do: name |> String.split() |> List.first("")

  attr :user, User, required: true

  def direct_placeholder(assigns) do
    ~H"""
    <form class="button_to" method="post" action={"/rooms/directs?user_ids%5B%5D=#{@user.id}"}>
      <button
        class="direct borderless fill-transparent unpad"
        type="submit"
      >
        <span class="avatar">
          <img aria-hidden="true" src={avatar_path(@user)} />
        </span>

        <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
          <span class="txt-nowrap overflow-ellipsis">
            <span class="for-screen-reader">Start a ping with</span>
            {first_word(@user.name)}
          </span>
        </span>
      </button><.csrf_input />
    </form>
    """
  end

  defp can_create_rooms?(user) do
    User.administrator?(user) or
      not Account.restrict_room_creation_to_administrators?(Campfire.Accounts.account())
  end
end
