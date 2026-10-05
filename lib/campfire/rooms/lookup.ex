defmodule Campfire.Rooms.Lookup do
  @moduledoc """
  Room queries the room page and the message views need: the viewer's membership, display
  names (directs are named after their members), the original room.
  """
  import Ecto.Query

  alias Campfire.Accounts.User
  alias Campfire.Repo.Replica
  alias Campfire.Rooms.{Membership, Room}

  @doc "The user's membership of the room (any involvement) with the room, or `nil`."
  def membership(user_id, room_id) do
    with {room_id, ""} <- Integer.parse(to_string(room_id)) do
      Replica.one(
        from m in Membership,
          join: r in assoc(m, :room),
          where: m.user_id == ^user_id and m.room_id == ^room_id,
          preload: [room: r]
      )
    else
      _ -> nil
    end
  end

  @doc "Names of a room's members, by user id (the order Rails' `room.users` comes back in)."
  def member_names(room_id) do
    Replica.all(
      from u in User,
        join: m in Membership,
        on: m.user_id == u.id,
        where: m.room_id == ^room_id,
        order_by: u.id,
        select: {u.id, u.name}
    )
  end

  @doc """
  Rails `room_display_name(room, for_user:)`: a direct room is named after its members other
  than `for_user` (`A`, `A and B`, `A, B, and C`), or `for_user`'s name if alone. `for_user`
  is `nil` in message partials (all members).
  """
  def display_name(%Room{type: :direct, id: id}, for_user) do
    names = for {uid, name} <- member_names(id), for_user == nil or uid != for_user.id, do: name

    case names do
      [] -> for_user && for_user.name
      names -> to_sentence(names)
    end
  end

  def display_name(%Room{name: name}, _for_user), do: name

  def to_sentence([one]), do: one
  def to_sentence([a, b]), do: "#{a} and #{b}"
  def to_sentence(list), do: Enum.join(Enum.drop(list, -1), ", ") <> ", and " <> List.last(list)

  @doc "Rails `Room.original`: the oldest room of all."
  def original_room_id do
    Replica.one(from r in Room, order_by: [asc: r.created_at, asc: r.id], limit: 1, select: r.id)
  end
end
