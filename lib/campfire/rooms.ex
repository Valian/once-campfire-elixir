defmodule Campfire.Rooms do
  @moduledoc """
  Rooms and memberships: the sidebar's reads, room display names, and creating, converting,
  revising and destroying rooms.

  Writes return the data callers need to broadcast (the room, its member ids); broadcasting
  itself is the web layer's job (`CampfireWeb.RoomBroadcasts`).
  """
  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Accounts.User
  alias Campfire.Rooms.{Membership, Room}
  alias Campfire.Schema.Timestamp

  @direct_placeholders 20

  ## Lookups

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

  @doc "The user's room with the highest id (`GET /rooms`)."
  def latest_room(user_id) do
    Replica.one(from r in for_user(user_id), order_by: [desc: r.id], limit: 1)
  end

  @doc """
  A room the user is a member of, or `nil`. `types` narrows it, as Rails' per-controller
  `room_scope` does (open/closed controllers can't reach directs and vice versa).
  """
  def get_room_for_user(user_id, room_id, types \\ [:open, :closed, :direct]) do
    if id = Campfire.Id.parse(room_id),
      do: Replica.one(from r in for_user(user_id), where: r.id == ^id and r.type in ^types)
  end

  @doc "The user's membership of a room, with the room preloaded; `nil` if not a member."
  def get_membership(user_id, room_id) do
    if id = Campfire.Id.parse(room_id) do
      Replica.one(
        from m in Membership,
          join: r in assoc(m, :room),
          where: m.user_id == ^user_id and m.room_id == ^id,
          preload: [room: r]
      )
    end
  end

  @doc "Active users, `ORDER BY LOWER(name)` (Rails `User.active.ordered`)."
  def active_users do
    Replica.all(
      from u in User, where: u.status == :active, order_by: fragment("LOWER(?)", u.name)
    )
  end

  # Rails' `room.users` has no ORDER BY; SQLite walks the covering (room_id, user_id) index, so
  # members come back by user id. Display names depend on it.

  @doc "A room's members, in Rails' `room.users` order (user id)."
  def members(%Room{id: room_id}) do
    Replica.all(
      from u in User,
        join: m in Membership,
        on: m.user_id == u.id,
        where: m.room_id == ^room_id,
        order_by: m.user_id
    )
  end

  def member_ids(%Room{id: room_id}) do
    Replica.all(from m in Membership, where: m.room_id == ^room_id, select: m.user_id)
  end

  @doc """
  `%{room_id => [user]}` for the given rooms, members by user id: one query for
  any number of (direct) rooms, so lists of rooms don't N+1 on their display names.
  """
  def members_by_room([]), do: %{}

  def members_by_room(room_ids) do
    from(m in Membership,
      join: u in assoc(m, :user),
      where: m.room_id in ^room_ids,
      order_by: [m.room_id, m.user_id],
      select: {m.room_id, u}
    )
    |> Replica.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Rails `room_display_name(room, for_user:)`: a non-direct room's name; for a direct room the
  names of its members other than `for_user` as a sentence, or `for_user`'s name if alone.
  `for_user` is `nil` in message partials (every member is named).
  """
  def display_name(%Room{type: :direct}, members, for_user) do
    others = if for_user, do: Enum.reject(members, &(&1.id == for_user.id)), else: members

    case others do
      [] -> for_user && for_user.name
      others -> others |> Enum.map(& &1.name) |> to_sentence()
    end
  end

  def display_name(%Room{name: name}, _members, _for_user), do: name

  @doc "`display_name/3` of one room, loading its members if it's a direct room."
  def display_name(%Room{type: :direct} = room, for_user),
    do: display_name(room, members(room), for_user)

  def display_name(%Room{name: name}, _for_user), do: name

  @doc "`%{room_id => display name}` for message partials (`for_user: nil`), in one query."
  def display_names(rooms) do
    members =
      rooms |> Enum.filter(&(&1.type == :direct)) |> Enum.map(& &1.id) |> members_by_room()

    Map.new(rooms, &{&1.id, display_name(&1, Map.get(members, &1.id, []), nil)})
  end

  @doc "Rails `Room.original`: the oldest room of all."
  def original_room_id do
    Replica.one(from r in Room, order_by: [asc: r.created_at, asc: r.id], limit: 1, select: r.id)
  end

  @doc "Rails `Array#to_sentence`: `A`, `A and B`, `A, B, and C`."
  def to_sentence(words, two_words_connector \\ " and ")
  def to_sentence([], _), do: ""
  def to_sentence([one], _), do: one
  def to_sentence([a, b], connector), do: a <> connector <> b

  def to_sentence(words, _) do
    {init, [last]} = Enum.split(words, -1)
    Enum.join(init, ", ") <> ", and " <> last
  end

  ## Sidebar

  @doc """
  What `GET /users/me/sidebar` shows, in three queries:

    * `:directs` — `{membership, members}` for visible direct rooms, most recently active
      first; `members` are the other members (or the user alone);
    * `:shared` — memberships of visible open/closed rooms, by room name;
    * `:placeholders` — active users without a direct room with the user, to start one with.
  """
  def sidebar(%User{id: user_id} = user) do
    memberships =
      Replica.all(
        from m in Membership,
          join: r in assoc(m, :room),
          where: m.user_id == ^user_id and m.involvement != ^:invisible,
          order_by: fragment("LOWER(?)", r.name),
          preload: [room: r],
          select: [:id, :room_id, :unread_at, room: [:id, :name, :type, :updated_at]]
      )

    {directs, shared} = Enum.split_with(memberships, &(&1.room.type == :direct))

    # Members of all the user's direct rooms, visible or not (Rails excludes them all from
    # the placeholders).
    direct_members =
      Replica.all(
        from m in Membership,
          join: u in assoc(m, :user),
          where:
            m.room_id in subquery(
              from mm in Membership,
                join: r in assoc(mm, :room),
                where: mm.user_id == ^user_id and r.type == ^:direct,
                select: mm.room_id
            ),
          order_by: m.id,
          select: {m.room_id, struct(u, [:id, :name, :updated_at])}
      )

    members = Enum.group_by(direct_members, &elem(&1, 0), &elem(&1, 1))

    directs =
      directs
      |> Enum.sort_by(&DateTime.to_unix(&1.room.updated_at, :microsecond), :desc)
      |> Enum.map(fn membership ->
        case Enum.reject(Map.get(members, membership.room_id, []), &(&1.id == user_id)) do
          [] -> {membership, [user]}
          others -> {membership, others}
        end
      end)

    %{directs: directs, shared: shared, placeholders: placeholders(user, direct_members)}
  end

  defp placeholders(%User{id: user_id}, direct_members) do
    excluded = direct_members |> Enum.map(fn {_, u} -> u.id end) |> Enum.uniq()
    # Rails counts the user twice here (`ids.uniq.including(current_user.id)` appends even
    # when present), so one fewer placeholder shows. Kept: it's what the page looks like.
    limit = max(@direct_placeholders - (length(excluded) + 1), 0)

    if limit > 0 do
      excluded = [user_id | excluded]

      Replica.all(
        from u in User,
          where: u.status == :active and u.id not in ^excluded,
          order_by: u.created_at,
          limit: ^limit,
          select: [:id, :name, :updated_at]
      )
    else
      []
    end
  end

  @doc """
  All of the user's memberships (any involvement) with rooms, by room name, split into
  `{directs, shared}`, plus the members of the direct rooms (for their names). Profile page.
  """
  def memberships_with_rooms(user_id) do
    memberships =
      Replica.all(
        from m in Membership,
          join: r in assoc(m, :room),
          where: m.user_id == ^user_id,
          order_by: fragment("LOWER(?)", r.name),
          preload: [room: r]
      )

    {directs, shared} = Enum.split_with(memberships, &(&1.room.type == :direct))
    {directs, shared, members_by_room(Enum.map(directs, & &1.room_id))}
  end

  ## Creating and changing rooms

  @doc "Rails `Room#default_involvement`."
  def default_involvement(:direct), do: :everything
  def default_involvement(_), do: :mentions

  @doc """
  Creates an open room: the creator first, then every active user, as Rails'
  `after_save_commit :grant_access_to_all_users` does.
  """
  def create_open_room(%User{} = creator, name) do
    transact(fn ->
      room = insert_room!(:open, name, creator)
      grant!(room, [creator.id])
      grant!(room, active_user_ids())
      room
    end)
  end

  @doc "Creates a closed room for the given users (the form includes the creator)."
  def create_closed_room(%User{} = creator, name, user_ids) do
    transact(fn ->
      room = insert_room!(:closed, name, creator)
      grant!(room, existing_user_ids(user_ids))
      room
    end)
  end

  @doc """
  Rails `Rooms::Direct.find_or_create_for`: the direct room whose member set is exactly
  `user_ids` (found in SQL rather than by scanning every direct room), else a new one.
  Returns `{:existing | :created, room}`.
  """
  def find_or_create_direct_room(%User{} = creator, user_ids) do
    # Look up and insert in one writer transaction: two quick submits make one room.
    transact(fn ->
      ids = existing_user_ids([creator.id | user_ids])
      count = length(ids)

      existing =
        Repo.one(
          from r in Room,
            join: m in Membership,
            on: m.room_id == r.id,
            where: r.type == ^:direct,
            group_by: r.id,
            having:
              count(m.id) == ^count and
                fragment("SUM(CASE WHEN ? THEN 1 ELSE 0 END)", m.user_id in ^ids) == ^count,
            order_by: r.id,
            limit: 1
        )

      case existing do
        %Room{} = room ->
          {:existing, room}

        nil ->
          room = insert_room!(:direct, nil, creator)
          grant!(room, ids)
          {:created, room}
      end
    end)
  end

  @doc """
  Renames a room and (re)sets its type: Rails' open/closed controllers "become" their type on
  update, so submitting an open room's form to the closed controller converts it. Converting
  to open grants every active user. With `grantee_ids` (closed rooms), grants those users and
  revokes everyone else; returns `{room, revoked_user_ids}`.
  """
  def update_room(%Room{type: from_type} = room, to_type, name, grantee_ids \\ nil)
      when to_type in [:open, :closed] and from_type in [:open, :closed] do
    transact(fn ->
      room =
        room
        |> Ecto.Changeset.change(type: to_type, name: name, updated_at: Timestamp.utc_now())
        |> Repo.update!()

      if to_type == :open and from_type != :open, do: grant!(room, active_user_ids())

      revoked =
        case grantee_ids do
          nil -> []
          ids -> revise!(room, existing_user_ids(ids))
        end

      {room, revoked}
    end)
  end

  defp revise!(room, grantee_ids) do
    grant!(room, grantee_ids)

    {_, revoked} =
      Repo.delete_all(
        from(m in Membership,
          where: m.room_id == ^room.id and m.user_id not in ^grantee_ids,
          select: m.user_id
        )
      )

    revoked
  end

  @doc """
  Destroys a room and everything in it (memberships, messages with their boosts, bodies,
  attachments and search index rows). Attachment blobs and files are left in place.
  """
  def destroy_room(%Room{id: room_id} = room) do
    message_ids = from(m in "messages", where: m.room_id == ^room_id, select: m.id)

    transact(fn ->
      Repo.delete_all(from b in "boosts", where: b.message_id in subquery(message_ids))

      Repo.delete_all(
        from t in "action_text_rich_texts",
          where: t.record_type == "Message" and t.record_id in subquery(message_ids)
      )

      Repo.delete_all(
        from a in "active_storage_attachments",
          where: a.record_type == "Message" and a.record_id in subquery(message_ids)
      )

      Repo.query!(
        "DELETE FROM message_search_index WHERE rowid IN (SELECT id FROM messages WHERE room_id = ?)",
        [room_id]
      )

      Repo.delete_all(from m in "messages", where: m.room_id == ^room_id)
      Repo.delete_all(from m in Membership, where: m.room_id == ^room_id)
      Repo.delete!(room)
    end)
  end

  ## Involvement

  @involvements ~w(invisible nothing mentions everything)

  @doc "Changes a membership's involvement. Returns `{:ok, membership}` or `:error`."
  def update_involvement(%Membership{} = membership, involvement)
      when involvement in @involvements do
    involvement = String.to_existing_atom(involvement)

    membership =
      membership
      |> Ecto.Changeset.change(involvement: involvement, updated_at: Timestamp.utc_now())
      |> Repo.update!()

    {:ok, membership}
  end

  def update_involvement(_, _), do: :error

  @doc "The bell's cycle: shared `mentions → everything → nothing → invisible`; direct `everything ⇄ nothing`."
  def next_involvement(%Room{type: :direct}, :everything), do: :nothing
  def next_involvement(%Room{type: :direct}, _), do: :everything
  def next_involvement(_, :mentions), do: :everything
  def next_involvement(_, :everything), do: :nothing
  def next_involvement(_, :nothing), do: :invisible
  def next_involvement(_, _), do: :mentions

  ## Helpers

  defp insert_room!(type, name, creator) do
    Repo.insert!(%Room{type: type, name: name, creator_id: creator.id})
  end

  # Rails `memberships.grant_to` (insert_all, skipping existing memberships).
  defp grant!(_room, []), do: :ok

  defp grant!(%Room{} = room, user_ids) do
    now = Timestamp.utc_now()
    involvement = default_involvement(room.type)

    rows =
      for id <- Enum.uniq(user_ids) do
        %{
          room_id: room.id,
          user_id: id,
          involvement: involvement,
          connections: 0,
          created_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Membership, rows, on_conflict: :nothing)
    :ok
  end

  defp active_user_ids do
    Repo.all(from u in User, where: u.status == :active, select: u.id)
  end

  defp existing_user_ids(ids) do
    ids = ids |> Enum.map(&Campfire.Id.parse/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    Repo.all(from u in User, where: u.id in ^ids, select: u.id, order_by: u.id)
  end

  defp transact(fun) do
    {:ok, result} = Repo.transaction(fun)
    result
  end
end
