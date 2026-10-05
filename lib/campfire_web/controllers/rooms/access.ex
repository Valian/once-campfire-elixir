defmodule CampfireWeb.Rooms.Access do
  @moduledoc "Plugs shared by the room controllers (Rails `RoomsController` before-actions)."
  import Plug.Conn
  import Phoenix.Controller

  alias Campfire.Accounts
  alias Campfire.Accounts.{Account, User}
  alias Campfire.Rooms

  @doc """
  Assigns `@room`: a room of one of `types` the user is a member of, else back to `/` with
  Rails' alert. Each controller only reaches its own types (open/closed convert into each
  other; directs never do).
  """
  def fetch_room(conn, types) do
    room_id = conn.params["id"] || conn.params["room_id"]

    case Rooms.get_room_for_user(conn.assigns.current_user.id, room_id, types) do
      nil ->
        conn
        |> put_flash(:alert, "Room not found or inaccessible")
        |> redirect(to: "/")
        |> halt()

      room ->
        assign(conn, :room, room)
    end
  end

  @doc "Administrators and the room's creator (Rails `ensure_can_administer`)."
  def ensure_can_administer(conn, _) do
    if User.can_administer?(conn.assigns.current_user, conn.assigns.room) do
      conn
    else
      conn |> send_resp(403, "") |> halt()
    end
  end

  @doc "403 for non-administrators when the account restricts room creation."
  def ensure_can_create_rooms(conn, _) do
    user = conn.assigns.current_user

    if User.administrator?(user) or
         not Account.restrict_room_creation_to_administrators?(Accounts.account()) do
      conn
    else
      conn |> send_resp(403, "") |> halt()
    end
  end

  @doc "Assigns `@last_room` for the back link (Rails `last_room_visited`)."
  def assign_last_room(conn, _) do
    room =
      Rooms.last_visited_room(
        conn.assigns.current_user.id,
        CampfireWeb.Plugs.last_room_id(conn)
      )

    assign(conn, :last_room, room)
  end

  @doc "`user_ids[]` as submitted (absent means none)."
  def user_ids(params) do
    case params["user_ids"] do
      ids when is_list(ids) -> ids
      _ -> []
    end
  end
end
