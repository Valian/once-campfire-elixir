defmodule CampfireWeb.Rooms.InvolvementController do
  use CampfireWeb, :controller

  alias Campfire.Rooms
  alias CampfireWeb.RoomBroadcasts

  plug :fetch_membership

  def show(conn, _params) do
    %{room: room, involvement: involvement} = conn.assigns.membership

    render(conn, :show,
      room: room,
      involvement: involvement || Rooms.default_involvement(room.type)
    )
  end

  def update(conn, params) do
    membership = conn.assigns.membership

    case Rooms.update_involvement(membership, params["involvement"]) do
      {:ok, updated} ->
        RoomBroadcasts.involvement_changed(
          %{updated | room: membership.room},
          membership.involvement
        )

        redirect(conn, to: ~p"/rooms/#{membership.room_id}/involvement")

      :error ->
        conn |> send_resp(422, "") |> halt()
    end
  end

  # Rails `RoomScoped`: the user's membership of the room, else 404.
  defp fetch_membership(conn, _) do
    case Rooms.get_membership(conn.assigns.current_user.id, conn.params["room_id"]) do
      nil -> conn |> send_resp(404, "") |> halt()
      membership -> assign(conn, :membership, membership)
    end
  end
end
