defmodule CampfireWeb.SearchController do
  use CampfireWeb, :controller

  import Ecto.Query

  alias Campfire.{Rooms, Searches}
  alias Campfire.Repo.Replica

  def index(conn, params) do
    user = conn.assigns.current_user
    query = Searches.sanitize_query(params["q"])
    results = if query, do: load_results(Searches.search_messages(user.id, query)), else: []

    conn
    |> assign(:query, query)
    |> assign(:q, params["q"])
    |> assign(:results, results)
    |> assign(:base_url, CampfireWeb.Plugs.base_url(conn))
    |> assign(:recent_searches, Searches.recent(user.id))
    |> assign(
      :return_to_room,
      Rooms.last_visited_room(user.id, CampfireWeb.Plugs.last_room_id(conn))
    )
    |> render(:index)
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    case Searches.sanitize_query(params["q"]) do
      nil ->
        redirect(conn, to: ~p"/searches")

      query ->
        :ok = Searches.record(user.id, query)
        redirect(conn, to: ~p"/searches?#{[q: query]}")
    end
  end

  def clear(conn, _params) do
    :ok = Searches.clear(conn.assigns.current_user.id)
    redirect(conn, to: ~p"/searches")
  end

  # Everything the result partial shows, in four queries for any number of results.
  defp load_results([]), do: []

  defp load_results(results) do
    messages =
      results
      |> Enum.map(&elem(&1, 0))
      |> Replica.preload([
        :creator,
        :room,
        boosts: {from(b in Campfire.Messages.Boost, order_by: [b.created_at, b.id]), :booster}
      ])

    direct_room_ids =
      for %{room: %{type: :direct, id: id}} <- messages, uniq: true, do: id

    members = Rooms.members_by_room(direct_room_ids)

    room_names =
      Map.new(messages, fn %{room: room} ->
        {room.id, Rooms.display_name(room, Map.get(members, room.id, []), nil)}
      end)

    Enum.zip_with(messages, results, fn message, {_, plain_text} ->
      %{message: message, plain_text: plain_text, room_name: room_names[message.room_id]}
    end)
  end
end
