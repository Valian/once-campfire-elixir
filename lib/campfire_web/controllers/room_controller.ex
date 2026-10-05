defmodule CampfireWeb.RoomController do
  @moduledoc """
  Rails `RoomsController`: `GET /rooms`, the room page (`GET /rooms/:id`,
  `GET /rooms/:room_id/@:message_id`, SPEC §7) and `DELETE /rooms/:id`.
  """
  use CampfireWeb, :controller

  import CampfireWeb.Rooms.Access

  alias Campfire.Accounts
  alias Campfire.Messages
  alias Campfire.Messages.Message
  alias Campfire.Rooms
  alias CampfireWeb.{MessageRenderer, Platform, RoomBroadcasts}

  @twenty_years 20 * 365 * 24 * 60 * 60

  plug :fetch_room, [:open, :closed, :direct] when action == :delete
  plug :ensure_can_administer when action == :delete

  def index(conn, _params) do
    case Rooms.latest_room(conn.assigns.current_user.id) do
      nil -> redirect(conn, to: "/")
      room -> redirect(conn, to: "/rooms/#{room.id}")
    end
  end

  def show(conn, params) do
    user = conn.assigns.current_user

    case Rooms.get_membership(user.id, params["room_id"] || params["id"]) do
      nil ->
        conn |> put_flash(:alert, "Room not found or inaccessible") |> redirect(to: ~p"/")

      %{room: room} ->
        messages =
          case params["message_id"] && Messages.get_in_room(room.id, params["message_id"]) do
            %Message{} = message -> Messages.page_around(room, message)
            _ -> Messages.last_page(room)
          end

        base_url = CampfireWeb.Plugs.base_url(conn)

        conn
        |> put_resp_cookie("last_room", Integer.to_string(room.id),
          max_age: @twenty_years,
          sign: false
        )
        |> render(:show,
          room: room,
          title: Rooms.display_name(room, user),
          messages: MessageRenderer.render(messages, MessageRenderer.ctx(conn)),
          invitation: invitation(room),
          base_url: base_url,
          platform: Platform.from_conn(conn),
          account: Accounts.account(),
          account_logo?: Accounts.account_logo?()
        )
    end
  end

  def delete(conn, _params) do
    room = conn.assigns.room
    Rooms.destroy_room(room)
    RoomBroadcasts.room_destroyed(room)
    redirect(conn, to: "/")
  end

  # The welcome block shows in the oldest room while it has no more than a page of messages.
  defp invitation(room), do: room.id == Rooms.original_room_id() and not Messages.paged?(room.id)
end
