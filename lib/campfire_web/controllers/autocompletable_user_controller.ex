defmodule CampfireWeb.AutocompletableUserController do
  @moduledoc """
  `GET /autocompletable/users`: `<lexxy-prompt-item>`s for the composer's mentions prompt
  (`filter`), or JSON for the ping autocomplete (`query`, `Accept: application/json`).
  """
  use CampfireWeb, :controller

  alias Campfire.{Accounts, Rooms}
  alias CampfireWeb.{AutocompletableUserHTML, Components}

  def index(conn, params) do
    query = present(params["filter"]) || present(params["query"])
    page = parse_page(params["page"])

    with {:ok, room_id} <- room_scope(conn, params["room_id"]) do
      users = Accounts.autocompletable_users(query, room_id: room_id, page: page)

      if json?(conn) do
        base_url = CampfireWeb.Plugs.base_url(conn)

        json(
          conn,
          Enum.map(users, fn user ->
            %{
              name: Phoenix.HTML.html_escape(user.name) |> Phoenix.HTML.safe_to_string(),
              value: user.id,
              avatar_url: base_url <> Components.avatar_path(user),
              sgid: Campfire.Signing.sgid("User", user.id)
            }
          end)
        )
      else
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, AutocompletableUserHTML.render_items(users))
      end
    else
      :not_found -> send_resp(conn, 404, "")
    end
  end

  # With `room_id`, only that room's members — and only if the user is in the room.
  defp room_scope(_conn, room_id) when room_id in [nil, ""], do: {:ok, nil}

  defp room_scope(conn, room_id) do
    case Rooms.get_room_for_user(conn.assigns.current_user.id, room_id) do
      nil -> :not_found
      room -> {:ok, room.id}
    end
  end

  defp json?(conn) do
    conn |> get_req_header("accept") |> Enum.any?(&String.contains?(&1, "application/json"))
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
