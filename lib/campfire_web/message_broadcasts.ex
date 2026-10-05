defmodule CampfireWeb.MessageBroadcasts do
  @moduledoc """
  What message changes broadcast (SPEC §11.4), through `CampfireWeb.Cable.broadcast/2`. Each
  payload is rendered once, whatever the number of subscribers; the message partial carries no
  CSRF token (Turbo sends the header with every form).
  """
  alias Campfire.Messages
  alias Campfire.Messages.{Boost, Message}
  alias Campfire.Rooms.Room
  alias CampfireWeb.{Cable, MessageComponents, MessageRenderer, RoomHTML, TurboStream}

  @doc "A new message: appended to the room, and an unread ping to every member (the author too)."
  def created(conn, %Message{} = message, %Room{} = room) do
    html = MessageRenderer.render_one(message, MessageRenderer.broadcast_ctx(conn))
    Cable.broadcast(stream(room), TurboStream.append(RoomHTML.dom_id(room, "messages"), html))

    payload = %{"roomId" => room.id}

    for user_id <- Messages.member_ids(room.id),
        do: Cable.broadcast("user_#{user_id}_unreads", payload)

    :ok
  end

  @doc "An edited message: its presentation replaced in place."
  def updated(%Message{} = message, %Room{} = room) do
    target = "presentation_message_#{message.client_message_id}"
    content = MessageRenderer.presentation(%{message | room: room})
    Cable.broadcast(stream(room), TurboStream.replace(target, content, maintain_scroll: "true"))
  end

  def destroyed(%Message{} = message, %Room{} = room),
    do: Cable.broadcast(stream(room), TurboStream.remove("message_#{message.client_message_id}"))

  def boost_created(%Boost{} = boost, %Message{} = message, %Room{} = room) do
    content = MessageComponents.to_iodata(&MessageComponents.boost/1, %{boost: boost, csrf: ""})
    target = "boosts_message_#{message.client_message_id}"
    Cable.broadcast(stream(room), TurboStream.append(target, content, maintain_scroll: "true"))
  end

  def boost_destroyed(%Boost{id: id}, %Room{} = room),
    do: Cable.broadcast(stream(room), TurboStream.remove("boost_#{id}"))

  defp stream(room), do: RoomHTML.messages_stream(room)
end
