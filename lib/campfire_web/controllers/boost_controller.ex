defmodule CampfireWeb.BoostController do
  @moduledoc "Boosts of a message the user can reach (`/messages/:message_id/boosts`, SPEC §8.2)."
  use CampfireWeb, :controller

  alias Campfire.Messages
  alias Campfire.Repo.Replica
  alias CampfireWeb.MessageBroadcasts

  plug :put_message

  def index(conn, _params) do
    message = %{conn.assigns.message | boosts: Messages.boosts(conn.assigns.message)}
    render(conn, :index, message: message)
  end

  def new(conn, _params), do: render(conn, :new, message: conn.assigns.message)

  def create(conn, params) do
    message = conn.assigns.message

    case Messages.create_boost(
           message,
           conn.assigns.current_user,
           get_in(params, ["boost", "content"])
         ) do
      {:ok, boost} ->
        MessageBroadcasts.boost_created(boost, message, message.room)
        redirect(conn, to: ~p"/messages/#{message.id}/boosts")

      {:error, _} ->
        send_resp(conn, 422, "")
    end
  end

  def destroy(conn, %{"id" => id}) do
    message = conn.assigns.message

    case Messages.get_own_boost(message, conn.assigns.current_user, id) do
      nil ->
        send_resp(conn, 404, "")

      boost ->
        {:ok, _} = Messages.destroy_boost(boost, message)
        MessageBroadcasts.boost_destroyed(boost, message.room)
        send_resp(conn, 204, "")
    end
  end

  defp put_message(conn, _) do
    case Messages.get_reachable(conn.assigns.current_user.id, conn.params["message_id"]) do
      nil -> conn |> send_resp(404, "") |> halt()
      message -> assign(conn, :message, Replica.preload(message, [:room, :creator]))
    end
  end
end
