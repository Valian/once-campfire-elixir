defmodule CampfireWeb.MessageRenderer do
  @moduledoc """
  Renders message partials (room page, messages page, refresh, POST response, broadcasts,
  search) through a fragment cache.

  A partial depends on the message (and so its `updated_at`, which edits and boosts bump), its
  creator, its room's name, and on two things that vary by request: the CSRF token its forms
  carry and the host of its copy-link URL. It is rendered once with placeholders for those two,
  split at them, and cached in ETS; serving it interleaves the parts with the request's values.
  Cached parts are large binaries, so ETS hands them out by reference.

  The cache key is `{id, updated_at, creator's updated_at, room name}`; stale entries are
  replaced on the next miss and the table is cleared when it grows past `@max_entries`.
  """
  use GenServer

  require Logger

  alias Campfire.Messages
  alias Campfire.Messages.Message
  alias Campfire.RichText
  alias Campfire.Rooms
  alias CampfireWeb.MessageComponents

  @table __MODULE__
  @max_entries 2000

  @type ctx :: %{csrf: binary, base_url: binary}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Unguessable, so no message body can contain them.
    hole = Base.encode16(:crypto.strong_rand_bytes(12))

    :persistent_term.put(
      {__MODULE__, :holes},
      {"\u0001c" <> hole <> "\u0001", "\u0001u" <> hole <> "\u0001"}
    )

    {:ok, nil}
  end

  @doc "The context of the request: its CSRF token and `scheme://host[:port]`."
  def ctx(conn),
    do: %{csrf: Phoenix.Controller.get_csrf_token(), base_url: escaped_base_url(conn)}

  @doc "For broadcasts: no viewer, so no token (Turbo sends the header anyway)."
  def broadcast_ctx(conn), do: %{csrf: "", base_url: escaped_base_url(conn)}

  # The host comes from the request; it is filled into an attribute unescaped otherwise.
  defp escaped_base_url(conn),
    do:
      conn
      |> CampfireWeb.Plugs.base_url()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  @doc """
  The partials of `messages` (each with `creator` and `room` loaded), as iodata. Misses are
  preloaded and rendered together: one query per association, one for mentioned users.
  """
  @spec render([Message.t()], ctx) :: iodata
  def render([], _ctx), do: []

  def render(messages, ctx) do
    keyed = Enum.map(messages, &{key(&1), &1})

    cached =
      Map.new(keyed, fn {key, %Message{id: id}} ->
        case :ets.lookup(@table, id) do
          [{^id, ^key, parts}] -> {id, parts}
          _ -> {id, nil}
        end
      end)

    missing = for {key, m} <- keyed, cached[m.id] == nil, do: {key, m}
    fresh = render_missing(missing)

    Enum.map(messages, fn %Message{id: id} -> fill(cached[id] || fresh[id], ctx) end)
  end

  def render_one(%Message{} = message, ctx), do: render([message], ctx)

  @doc "The presentation div alone (the update broadcast's payload)."
  def presentation(%Message{} = message) do
    [message] = Messages.preload_presentation([message], room_of(message))
    tree = Messages.body_tree(message)
    {content, _emoji} = body(message, tree, Messages.mentioned_users([tree]))

    MessageComponents.to_iodata(&MessageComponents.presentation/1, %{
      message: message,
      content: {:safe, content}
    })
  end

  defp room_of(%Message{room: %Campfire.Rooms.Room{} = room}), do: room
  defp room_of(_), do: nil

  defp key(%Message{} = m),
    do: {m.updated_at, m.creator && m.creator.updated_at, m.room && m.room.name}

  defp render_missing([]), do: %{}

  defp render_missing(missing) do
    messages =
      missing
      |> Enum.map(fn {_, m} -> m end)
      |> Messages.preload_presentation(common_room(missing))

    trees = Map.new(messages, &{&1.id, Messages.body_tree(&1)})
    users = Messages.mentioned_users(Map.values(trees))
    room_names = room_names(messages)
    {csrf_hole, url_hole} = holes()

    rendered =
      Map.new(messages, fn message ->
        parts =
          message
          |> render_partial(
            trees[message.id],
            users,
            room_names[message.room_id],
            csrf_hole,
            url_hole
          )
          |> IO.iodata_to_binary()
          |> split(csrf_hole, url_hole)

        {message.id, parts}
      end)

    if :ets.info(@table, :size) > @max_entries, do: :ets.delete_all_objects(@table)
    keys = Map.new(missing, fn {key, m} -> {m.id, key} end)
    :ets.insert(@table, for({id, parts} <- rendered, do: {id, keys[id], parts}))
    rendered
  end

  defp common_room([{_, %Message{room: room}} | rest]) do
    if Enum.all?(rest, fn {_, m} -> m.room_id == room.id end), do: room
  end

  # Direct rooms are named after their members (`room_display_name(room, for_user: nil)`).
  defp room_names(messages) do
    messages
    |> Enum.map(& &1.room)
    |> Enum.uniq_by(& &1.id)
    |> Rooms.display_names()
  end

  # A message that can't be rendered (its creator is gone, say) shows as such, as in Rails.
  defp render_partial(%Message{creator: nil}, _tree, _users, _room_name, _c, _u),
    do: unrenderable()

  defp render_partial(message, tree, users, room_name, csrf_hole, url_hole) do
    {presentation, emoji} = body(message, tree, users)

    MessageComponents.to_iodata(&MessageComponents.message/1, %{
      message: message,
      room_name: room_name,
      presentation: {:safe, presentation},
      emoji: emoji,
      csrf: csrf_hole,
      base_url: url_hole
    })
  rescue
    e ->
      Logger.error(
        "Failed to render message #{message.id}: " <> Exception.format(:error, e, __STACKTRACE__)
      )

      unrenderable()
  end

  defp unrenderable, do: MessageComponents.to_iodata(&MessageComponents.unrenderable/1, %{})

  # {presentation iodata, all-emoji?}. No request host: the partial is shared across hosts, so
  # an unfurl pointing at this Campfire's own host isn't recognized as such (Rails drops it).
  defp body(message, tree, users) do
    blob = message.attachment && message.attachment.blob
    plain = Messages.plain_text_body(tree, users, blob)

    cond do
      blob ->
        {MessageComponents.to_iodata(&MessageComponents.attachment/1, %{blob: blob}),
         RichText.all_emoji?(plain)}

      sound = MessageComponents.sound_for(plain) ->
        {name, sound} = sound

        {MessageComponents.to_iodata(&MessageComponents.sound/1, %{name: name, sound: sound}),
         false}

      true ->
        ctx = %{users: users, host: nil, mention: &CampfireWeb.Mention.nodes(&1, :presentation)}
        {RichText.presentation(tree, ctx), RichText.all_emoji?(plain)}
    end
  end

  defp holes, do: :persistent_term.get({__MODULE__, :holes})

  # Parts: binaries and the atoms :csrf / :base_url where the request's values go.
  defp split(binary, csrf_hole, url_hole) do
    binary
    |> :binary.split(csrf_hole, [:global])
    |> Enum.intersperse(:csrf)
    |> Enum.flat_map(fn
      :csrf -> [:csrf]
      part -> part |> :binary.split(url_hole, [:global]) |> Enum.intersperse(:base_url)
    end)
  end

  defp fill(parts, %{csrf: csrf, base_url: base_url}) do
    Enum.map(parts, fn
      :csrf -> csrf
      :base_url -> base_url
      part -> part
    end)
  end

  @doc "Empties the cache (tests)."
  def clear, do: :ets.delete_all_objects(@table)
end
