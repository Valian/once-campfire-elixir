defmodule CampfireWeb.RoomController do
  @moduledoc "The room page: `GET /rooms/:id` and `GET /rooms/:room_id/@:message_id` (SPEC §7)."
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias Campfire.Messages
  alias Campfire.Messages.Message
  alias Campfire.Rooms.Lookup
  alias CampfireWeb.{MessageRenderer, Platform}

  @twenty_years 20 * 365 * 24 * 60 * 60

  def show(conn, params) do
    user = conn.assigns.current_user

    case Lookup.membership(user.id, params["room_id"] || params["id"]) do
      nil ->
        conn |> put_flash(:alert, "Room not found or inaccessible") |> redirect(to: ~p"/")

      %{room: room} ->
        messages =
          case params["message_id"] && Messages.get_in_room(room.id, params["message_id"]) do
            %Message{} = message -> Messages.page_around(room, message)
            _ -> Messages.last_page(room)
          end

        base_url = MessageRenderer.base_url(conn)

        conn
        |> put_resp_cookie("last_room", Integer.to_string(room.id),
          max_age: @twenty_years,
          sign: false
        )
        |> render(:show,
          room: room,
          title: Lookup.display_name(room, user),
          messages: MessageRenderer.render(messages, MessageRenderer.ctx(conn)),
          invitation: invitation(room),
          base_url: base_url,
          platform: Platform.from_conn(conn),
          account: Accounts.account(),
          account_logo?: Accounts.account_logo?()
        )
    end
  end

  # The welcome block shows in the oldest room while it has no more than a page of messages.
  defp invitation(room), do: room.id == Lookup.original_room_id() and not Messages.paged?(room.id)
end
