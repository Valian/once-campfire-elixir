defmodule Campfire.Rooms do
  @moduledoc "Rooms and memberships."
  import Ecto.Query

  alias Campfire.Repo.Replica
  alias Campfire.Rooms.{Membership, Room}

  @doc "Rooms the user is a member of (any involvement)."
  def for_user(user_id) do
    from r in Room, join: m in Membership, on: m.room_id == r.id and m.user_id == ^user_id
  end

  @doc """
  Where `/` sends a user: the room from the `last_room` cookie if they're still a member,
  else their oldest room (Rails `rooms.original`). `nil` if they have no rooms.
  """
  def last_visited_room(user_id, last_room_id) do
    with id when is_integer(id) <- last_room_id,
         %Room{} = room <- Replica.one(from r in for_user(user_id), where: r.id == ^id) do
      room
    else
      _ -> Replica.one(from r in for_user(user_id), order_by: r.created_at, limit: 1)
    end
  end
end
