defmodule CampfireWeb.RefreshController do
  @moduledoc """
  `GET /rooms/:room_id/refresh?since={ms}`: what changed while the page wasn't listening (the
  client asks on every cable reconnect). New messages are appended; updated ones replaced.
  """
  use CampfireWeb, :controller

  alias Campfire.Messages
  alias Campfire.Rooms
  alias CampfireWeb.{MessageRenderer, RoomHTML, TurboStream}

  def show(conn, %{"room_id" => room_id} = params) do
    case Rooms.get_membership(conn.assigns.current_user.id, room_id) do
      nil ->
        send_resp(conn, 404, "")

      %{room: room} ->
        since = since(params["since"])
        new = Messages.created_since(room, since)
        updated = Messages.updated_since(room, since, Enum.map(new, & &1.id))
        ctx = MessageRenderer.ctx(conn)

        appended =
          if new == [],
            do: [],
            else:
              TurboStream.append(
                RoomHTML.dom_id(room, "messages"),
                MessageRenderer.render(new, ctx)
              )

        # One render call for all of them: cache misses are preloaded together.
        replaced =
          Enum.zip_with(updated, MessageRenderer.render(updated, ctx), fn message, html ->
            TurboStream.replace("message_#{message.client_message_id}", html)
          end)

        TurboStream.send(conn, [appended, replaced])
    end
  end

  # `Time.at(0, since.to_i, :millisecond)`: anything unparseable is the epoch.
  defp since(value) do
    ms =
      with value when is_binary(value) <- value,
           {ms, _} <- Integer.parse(value) do
        ms
      else
        _ -> 0
      end

    case DateTime.from_unix(ms, :millisecond) do
      {:ok, time} -> time
      {:error, _} -> DateTime.from_unix!(0)
    end
  end
end
