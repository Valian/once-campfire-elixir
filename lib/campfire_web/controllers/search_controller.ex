defmodule CampfireWeb.SearchController do
  use CampfireWeb, :controller

  alias Campfire.{Messages, Rooms, Searches}
  alias CampfireWeb.MessageRenderer

  def index(conn, params) do
    user = conn.assigns.current_user
    query = Searches.sanitize_query(params["q"])
    messages = if query, do: Searches.search_messages(user.id, query), else: []

    conn
    |> assign(:query, query)
    |> assign(:q, params["q"])
    |> assign(:result_count, length(messages))
    |> assign(
      :results,
      messages |> Messages.for_rendering() |> MessageRenderer.render(MessageRenderer.ctx(conn))
    )
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
end
