defmodule CampfireWeb.MessageController do
  @moduledoc "Messages of a room: pages, post, show, edit, update, delete (SPEC §8.4, §8.6)."
  use CampfireWeb, :controller

  alias Campfire.Accounts.User
  alias Campfire.Messages
  alias Campfire.Messages.Message
  alias Campfire.Rooms.Lookup
  alias CampfireWeb.{MessageBroadcasts, MessageRenderer, RoomHTML, TurboStream}

  plug :put_room when action != :create
  plug :put_message when action in [:show, :edit, :update, :destroy]
  plug :ensure_can_administer when action in [:edit, :update, :destroy]

  @doc "`?before=ID` / `?after=ID` / the last page: bare partials, 204 when there are none."
  def index(conn, params) do
    room = conn.assigns.room

    page =
      cond do
        id = presence(params["before"]) ->
          with %Message{} = m <- find(room, id), do: Messages.page_before(room, m)

        id = presence(params["after"]) ->
          with %Message{} = m <- find(room, id), do: Messages.page_after(room, m)

        true ->
          Messages.last_page(room)
      end

    case page do
      nil ->
        conn |> send_resp(404, "") |> halt()

      [] ->
        send_resp(conn, 204, "")

      messages ->
        last_modified = messages |> Enum.map(& &1.updated_at) |> Enum.max(DateTime)

        if fresh?(conn, last_modified) do
          send_resp(conn, 304, "")
        else
          conn
          |> put_resp_header("last-modified", http_date(last_modified))
          |> put_resp_content_type("text/html")
          |> send_resp(200, MessageRenderer.render(messages, MessageRenderer.ctx(conn)))
        end
    end
  end

  def create(conn, %{"room_id" => room_id} = params) do
    user = conn.assigns.current_user

    with %{room: room} <- Lookup.membership(user.id, room_id),
         {:ok, message} <- Messages.create_message(room, user, params["message"] || %{}) do
      [message] = Messages.with_creator([message], room)
      MessageBroadcasts.created(conn, message, room)

      html = MessageRenderer.render_one(message, MessageRenderer.ctx(conn))
      TurboStream.send(conn, TurboStream.append(RoomHTML.dom_id(room, "messages"), html))
    else
      nil -> conn |> put_resp_content_type("text/html") |> send_resp(200, room_not_found())
      {:error, :blank} -> send_resp(conn, 422, "")
    end
  end

  def show(conn, _params) do
    message = conn.assigns.message
    html = MessageRenderer.render_one(message, MessageRenderer.ctx(conn))
    render(conn, :show, message: message, html: html)
  end

  def edit(conn, _params) do
    [message] = Messages.preload_presentation([conn.assigns.message], conn.assigns.room)
    tree = Messages.body_tree(message)
    users = Messages.mentioned_users([tree])

    render(conn, :edit,
      message: message,
      room: conn.assigns.room,
      editable:
        Campfire.RichText.editable(tree, %{users: users, host: nil, mention: &mention_editable/1}),
      attachment: message.attachment && message.attachment.blob
    )
  end

  def update(conn, params) do
    %{message: message, room: room} = conn.assigns
    body = get_in(params, ["message", "body"])
    {:ok, message} = Messages.update_body(message, body)
    MessageBroadcasts.updated(message, room)
    redirect(conn, to: ~p"/rooms/#{room.id}/messages/#{message.id}")
  end

  def destroy(conn, _params) do
    %{message: message, room: room} = conn.assigns
    {:ok, _} = Messages.destroy_message(message)
    MessageBroadcasts.destroyed(message, room)
    TurboStream.send(conn, TurboStream.remove("message_#{message.client_message_id}"))
  end

  ## Plugs

  # RoomScoped: the user's membership of the room, else 404.
  defp put_room(conn, _) do
    case Lookup.membership(conn.assigns.current_user.id, conn.params["room_id"]) do
      %{room: room} -> assign(conn, :room, room)
      nil -> conn |> send_resp(404, "") |> halt()
    end
  end

  defp put_message(conn, _) do
    case find(conn.assigns.room, conn.params["id"]) do
      %Message{} = message -> assign(conn, :message, message)
      nil -> conn |> send_resp(404, "") |> halt()
    end
  end

  defp ensure_can_administer(conn, _) do
    if User.can_administer?(conn.assigns.current_user, conn.assigns.message),
      do: conn,
      else: conn |> send_resp(403, "") |> halt()
  end

  defp find(room, id) do
    case Messages.get_in_room(room.id, id) do
      nil -> nil
      message -> message |> List.wrap() |> Messages.with_creator(room) |> hd()
    end
  end

  defp room_not_found do
    ~s(<turbo-frame id="composer-frame">\n  <span class="composer__input input input--actor shake margin-block-end txt-negative txt-align-center" style="--input-border-color: var\(--color-negative\)">\n      <span>This room was deleted.</span>\n  </span>\n</turbo-frame>\n)
  end

  # The editor gets the mention partial as Rails renders it (sgid included: Lexxy keeps it).
  defp mention_editable(user) do
    [
      {"span", [{"class", "mention"}, {"sgid", Campfire.Signing.sgid("User", user.id)}],
       [
         {"a",
          [
            {"title", User.title(user)},
            {"class", "btn avatar"},
            {"data-turbo-frame", "_top"},
            {"href", "/users/#{user.id}"}
          ],
          [
            {"img",
             [
               {"aria-hidden", "true"},
               {"src", CampfireWeb.Components.avatar_path(user)},
               {"width", "48"},
               {"height", "48"}
             ], []}
          ]},
         " " <> user.name
       ]}
    ]
  end

  defp fresh?(conn, last_modified) do
    with [since] <- get_req_header(conn, "if-modified-since"),
         {:ok, since} <- parse_http_date(since) do
      DateTime.compare(DateTime.truncate(last_modified, :second), since) != :gt
    else
      _ -> false
    end
  end

  defp http_date(dt), do: Calendar.strftime(dt, "%a, %d %b %Y %H:%M:%S GMT")

  defp parse_http_date(value) do
    case Regex.run(~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/, value) do
      [_, d, mon, y, h, mi, s] ->
        month = Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == mon))

        with false <- is_nil(month),
             {:ok, date} <- Date.new(String.to_integer(y), month + 1, String.to_integer(d)),
             {:ok, time} <-
               Time.new(String.to_integer(h), String.to_integer(mi), String.to_integer(s)) do
          DateTime.new(date, time)
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
