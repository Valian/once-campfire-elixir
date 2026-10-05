defmodule CampfireWeb.AvatarController do
  use CampfireWeb, :controller

  alias Campfire.Avatars
  alias CampfireWeb.AvatarCache

  @cache_control "max-age=1800, public, stale-while-revalidate=604800"

  @doc """
  `GET /users/:avatar_token/avatar`: the square webp, the bot SVG or the initials SVG, from
  `AvatarCache`. Images go out as-is (`no-transform` keeps Bandit from gzipping webp); SVGs
  are sent pre-gzipped when the client accepts it.
  """
  def show(conn, %{"avatar_token" => token}) do
    case AvatarCache.fetch(token) do
      {:ok, entry} -> send_avatar(conn, entry)
      :error -> send_resp(conn, 404, "")
    end
  end

  defp send_avatar(conn, %{etag: etag} = entry) do
    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("content-disposition", "inline")

    if etag in get_req_header(conn, "if-none-match") do
      conn |> put_resp_header("cache-control", @cache_control) |> send_resp(304, "")
    else
      send_body(conn, entry)
    end
  end

  defp send_body(conn, %{gzip: nil} = entry) do
    conn
    |> put_resp_header("content-type", entry.content_type)
    |> put_resp_header("cache-control", @cache_control <> ", no-transform")
    |> send_resp(200, entry.body)
  end

  defp send_body(conn, entry) do
    conn =
      conn
      |> put_resp_header("content-type", entry.content_type)
      |> put_resp_header("cache-control", @cache_control)
      |> put_resp_header("vary", "accept-encoding")

    if accepts_gzip?(conn) do
      conn |> put_resp_header("content-encoding", "gzip") |> send_resp(200, entry.gzip)
    else
      send_resp(conn, 200, entry.body)
    end
  end

  defp accepts_gzip?(conn) do
    conn |> get_req_header("accept-encoding") |> Enum.any?(&String.contains?(&1, "gzip"))
  end

  @doc "`DELETE /users/:user_id/avatar`: removes the current user's own avatar."
  def delete(conn, _params) do
    user = conn.assigns.current_user
    :ok = Avatars.remove(user)
    AvatarCache.forget(user.id)
    redirect(conn, to: ~p"/users/me/profile")
  end
end
