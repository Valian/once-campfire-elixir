defmodule Campfire.Messages do
  @moduledoc """
  Messages, their bodies, attachments and boosts.

  Reads go to the replica and come back with everything the message partial shows preloaded
  (`preload_presentation/2`). Writes are one writer transaction each; image work (analysis,
  thumbnail) runs before it, so the writer isn't held while libvips works.
  """
  import Ecto.Query

  alias Campfire.Accounts.User
  alias Campfire.Messages.{Boost, Message, RichText}
  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Rooms.{Membership, Room}
  alias Campfire.Schema.Timestamp
  alias Campfire.Storage

  @page_size 40

  ## Pages (Message::Pagination)
  #
  # Pages come back oldest first with `creator` (joined: the partial cache keys on it) and `room`
  # set; `preload_presentation/2` loads the rest for the partials that aren't cached.

  defp in_room(room_id), do: from(m in Message, where: m.room_id == ^room_id)

  @doc "The room's newest page."
  def last_page(%Room{} = room), do: room.id |> in_room() |> last_of(room)

  def page_before(%Room{} = room, %Message{created_at: at}),
    do: from(m in in_room(room.id), where: m.created_at < ^at) |> last_of(room)

  def page_after(%Room{} = room, %Message{created_at: at}),
    do: from(m in in_room(room.id), where: m.created_at > ^at) |> first_of(room)

  @doc "Up to 40 before `message`, the message, up to 40 after."
  def page_around(%Room{} = room, %Message{} = message) do
    [message] = with_creator([message], room)
    page_before(room, message) ++ [message] ++ page_after(room, message)
  end

  @doc "Messages created after `time` (the oldest 40)."
  def created_since(%Room{} = room, %DateTime{} = time),
    do: from(m in in_room(room.id), where: m.created_at > ^time) |> first_of(room)

  @doc "Messages updated after `time`, except `except_ids` (the newest 40)."
  def updated_since(%Room{} = room, %DateTime{} = time, except_ids) do
    from(m in in_room(room.id), where: m.updated_at > ^time and m.id not in ^except_ids)
    |> last_of(room)
  end

  defp last_of(query, room) do
    from(m in query, order_by: [desc: m.created_at, desc: m.id], limit: @page_size)
    |> fetch(room)
    |> Enum.reverse()
  end

  defp first_of(query, room),
    do:
      from(m in query, order_by: [asc: m.created_at, asc: m.id], limit: @page_size) |> fetch(room)

  defp fetch(query, room) do
    from(m in query,
      left_join: u in assoc(m, :creator),
      preload: [creator: u],
      select: [
        :id,
        :client_message_id,
        :room_id,
        :creator_id,
        :created_at,
        :updated_at,
        creator: [:id, :name, :bio, :updated_at]
      ]
    )
    |> Replica.all()
    |> Enum.map(&%{&1 | room: room})
  end

  @doc "Sets `room` and loads `creator` on messages (for rendering single messages)."
  def with_creator(messages, %Room{} = room) do
    messages
    |> Replica.preload(creator: presentation_users())
    |> Enum.map(&%{&1 | room: room})
  end

  @doc """
  Loads `creator` and `room`, which `CampfireWeb.MessageRenderer.render/2` needs, on messages
  from any rooms (search results).
  """
  def for_rendering(messages) do
    Replica.preload(messages,
      creator: presentation_users(),
      room: from(r in Room, select: [:id, :name, :type])
    )
  end

  defp presentation_users, do: from(u in User, select: [:id, :name, :bio, :updated_at])

  @doc "Whether the room has more than a page of messages (Rails `paged?`)."
  def paged?(room_id),
    do: Replica.exists?(from m in in_room(room_id), offset: @page_size, select: 1)

  def get_in_room(room_id, id) do
    if id = Campfire.Id.parse(id) do
      Replica.one(from m in in_room(room_id), where: m.id == ^id)
    end
  end

  @doc "A pagination cursor in this room; only its id and creation time are needed."
  def pagination_anchor(room_id, id) do
    if id = Campfire.Id.parse(id) do
      Replica.one(from m in in_room(room_id), where: m.id == ^id, select: [:id, :created_at])
    end
  end

  @doc "A message in one of the user's rooms (Rails `user.reachable_messages.find`)."
  def get_reachable(user_id, id) do
    if id = Campfire.Id.parse(id) do
      Replica.one(
        from m in Message,
          join: ms in Membership,
          on: ms.room_id == m.room_id and ms.user_id == ^user_id,
          where: m.id == ^id
      )
    end
  end

  @doc """
  Preloads what the message partial shows: creator, body, attachment blob, boosts with boosters,
  and `room` (pass it when known: every message of a page shares it).
  """
  def preload_presentation(messages, room \\ nil)
  def preload_presentation([], _room), do: []

  def preload_presentation(messages, room) do
    messages =
      Replica.preload(messages,
        creator: presentation_users(),
        rich_text: from(r in RichText, select: [:id, :record_id, :body]),
        attachment: [blob: []],
        boosts:
          {from(b in Boost,
             order_by: [asc: b.created_at, asc: b.id],
             select: [:id, :message_id, :booster_id, :content, :created_at]
           ), booster: presentation_users()}
      )

    case room do
      %Room{} -> Enum.map(messages, &%{&1 | room: room})
      nil -> Replica.preload(messages, room: from(r in Room, select: [:id, :name, :type]))
    end
  end

  ## Bodies

  @doc "The rich text tree of a message (`[]` without a body)."
  def body_tree(%Message{rich_text: %RichText{body: body}}), do: Campfire.RichText.parse(body)
  def body_tree(%Message{}), do: []

  @doc "Users mentioned across `trees`, by id, in one query."
  def mentioned_users(trees) do
    case trees |> Enum.flat_map(&Campfire.RichText.mentioned_user_ids/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        Replica.all(from u in presentation_users(), where: u.id in ^ids)
        |> Map.new(&{&1.id, &1})
    end
  end

  @doc "`Message#plain_text_body`: the body as plain text, else the attachment's filename."
  def plain_text_body(tree, users, blob) do
    case Campfire.RichText.plain_text(tree, %{users: users, host: nil}) do
      "" -> (blob && blob.filename) || ""
      text -> text
    end
  end

  ## Create

  @doc """
  Posts a message: `attrs` has `"body"` (HTML or plain text), `"attachment"` (a `Plug.Upload`)
  and `"client_message_id"`. Marks the room unread for members who aren't looking at it.

  The message comes back with everything the partial needs already set (creator, room, body,
  attachment, no boosts), so rendering it takes no queries.
  """
  def create_message(%Room{} = room, %User{} = creator, attrs) do
    body = presence(attrs["body"])
    upload = match?(%Plug.Upload{}, attrs["attachment"]) && attrs["attachment"]

    if body == nil and !upload do
      {:error, :blank}
    else
      tree = Campfire.RichText.parse(body)
      users = mentioned_users([tree])
      {blob, thumb} = if upload, do: store_attachment(upload), else: {nil, nil}
      plain = plain_text_body(tree, users, blob)
      now = Timestamp.utc_now()

      message = %Message{
        room_id: room.id,
        creator_id: creator.id,
        client_message_id: presence(attrs["client_message_id"]) || Ecto.UUID.generate(),
        created_at: now,
        updated_at: now
      }

      Repo.transaction(fn ->
        message = Repo.insert!(message)
        rich_text = if body, do: insert_body!(message, body, tree, now)
        attachment = if blob, do: insert_attachment!(message, blob, thumb)
        touch_room!(room.id, now)

        Repo.query!("INSERT INTO message_search_index(rowid, body) VALUES (?, ?)", [
          message.id,
          plain
        ])

        mark_unread!(room.id, creator.id, now)

        %{
          message
          | creator: creator,
            room: room,
            rich_text: rich_text,
            attachment: attachment,
            boosts: []
        }
      end)
    end
  end

  # The file goes into place and its thumbnail is rendered before the transaction starts.
  defp store_attachment(upload) do
    blob = Storage.store_upload(upload)

    thumb =
      if Storage.variable?(blob) do
        transformations = Storage.thumb(blob)

        case Storage.render_variant(blob, transformations) do
          {:ok, variant} -> {transformations, variant}
          :error -> nil
        end
      end

    {blob, thumb}
  end

  defp insert_attachment!(message, blob, thumb) do
    blob = Storage.insert_blob!(blob)
    attachment = Storage.attach!(blob, "Message", message.id, "attachment")

    with {transformations, variant} <- thumb,
         do: Storage.insert_variant!(blob, transformations, variant)

    %{attachment | blob: blob}
  end

  # Stored as submitted, except that attachments lose their inner HTML (Action Text's canonical form).
  defp insert_body!(message, body, tree, now) do
    Repo.insert!(%RichText{
      record_type: "Message",
      record_id: message.id,
      name: "body",
      body: stored_body(body, tree),
      created_at: now,
      updated_at: now
    })
  end

  defp stored_body(body, tree) do
    if String.contains?(body, "</action-text-attachment>") and
         Regex.match?(~r/<action-text-attachment[^>]*>(?!<\/action-text-attachment>)/, body),
       do: Campfire.RichText.HTML.to_binary(tree),
       else: body
  end

  defp touch_room!(room_id, now),
    do: Repo.update_all(from(r in Room, where: r.id == ^room_id), set: [updated_at: now])

  # Room#unread_memberships: visible, disconnected (no presence for 60 s), not the author.
  defp mark_unread!(room_id, creator_id, now) do
    cutoff = Campfire.Rooms.Presence.connected_since(now)

    Repo.update_all(
      from(m in Membership,
        where:
          m.room_id == ^room_id and m.involvement != :invisible and m.user_id != ^creator_id and
            (is_nil(m.connected_at) or m.connected_at < ^cutoff)
      ),
      set: [unread_at: now, updated_at: now]
    )
  end

  ## Update

  @doc "Replaces a message's body; touches the message and its room."
  def update_body(%Message{} = message, body) do
    body = body || ""
    tree = Campfire.RichText.parse(body)
    users = mentioned_users([tree])
    message = Replica.preload(message, attachment: [blob: []])
    plain = plain_text_body(tree, users, message.attachment && message.attachment.blob)
    now = Timestamp.utc_now()

    Repo.transaction(fn ->
      {count, _} =
        Repo.update_all(
          from(r in RichText,
            where: r.record_type == "Message" and r.record_id == ^message.id and r.name == "body"
          ),
          set: [body: stored_body(body, tree), updated_at: now]
        )

      if count == 0, do: insert_body!(message, body, tree, now)
      Repo.update_all(from(m in Message, where: m.id == ^message.id), set: [updated_at: now])
      touch_room!(message.room_id, now)
      Repo.query!("UPDATE message_search_index SET body = ? WHERE rowid = ?", [plain, message.id])
      %{message | updated_at: now}
    end)
  end

  ## Destroy

  @doc "Deletes a message with its boosts, body, attachment (files removed after commit) and index row."
  def destroy_message(%Message{id: id} = message) do
    now = Timestamp.utc_now()

    {:ok, keys} =
      Repo.transaction(fn ->
        keys = Storage.purge_attachments!("Message", id, "attachment")
        Repo.delete_all(from b in Boost, where: b.message_id == ^id)

        Repo.delete_all(
          from r in RichText, where: r.record_type == "Message" and r.record_id == ^id
        )

        Repo.query!("DELETE FROM message_search_index WHERE rowid = ?", [id])
        Repo.delete_all(from m in Message, where: m.id == ^id)
        touch_room!(message.room_id, now)
        keys
      end)

    Storage.delete_files(keys)
    {:ok, message}
  end

  ## Boosts

  @doc "Boosts a message (touching it and its room). Content: 1–16 characters, not blank."
  def create_boost(%Message{} = message, %User{} = booster, content) do
    content = content |> to_string() |> String.trim_trailing()

    if content == "" or String.length(content) > 16 do
      {:error, :invalid}
    else
      now = Timestamp.utc_now()

      Repo.transaction(fn ->
        boost =
          Repo.insert!(%Boost{
            message_id: message.id,
            booster_id: booster.id,
            content: content,
            created_at: now,
            updated_at: now
          })

        touch_message!(message, now)
        %{boost | booster: booster, message: message}
      end)
    end
  end

  def get_own_boost(%Message{id: message_id}, %User{id: user_id}, id) do
    if id = Campfire.Id.parse(id) do
      Replica.one(
        from b in Boost,
          where: b.id == ^id and b.message_id == ^message_id and b.booster_id == ^user_id
      )
    end
  end

  def destroy_boost(%Boost{} = boost, %Message{} = message) do
    now = Timestamp.utc_now()

    Repo.transaction(fn ->
      Repo.delete_all(from b in Boost, where: b.id == ^boost.id)
      touch_message!(message, now)
      boost
    end)
  end

  def boosts(%Message{id: id}) do
    Replica.all(
      from b in Boost,
        where: b.message_id == ^id,
        order_by: [asc: b.created_at, asc: b.id],
        preload: :booster
    )
  end

  defp touch_message!(message, now) do
    Repo.update_all(from(m in Message, where: m.id == ^message.id), set: [updated_at: now])
    touch_room!(message.room_id, now)
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp presence(_), do: nil
end
