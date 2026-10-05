defmodule CampfireWeb.SidebarController do
  use CampfireWeb, :controller

  alias Campfire.Rooms

  # `GET /users/:user_id/sidebar`: the id is always "me" in practice and is ignored.
  def show(conn, _params) do
    render(conn, :show, sidebar: Rooms.sidebar(conn.assigns.current_user))
  end
end
