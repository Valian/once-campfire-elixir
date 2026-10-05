defmodule CampfireWeb.SidebarTest do
  use CampfireWeb.ConnCase

  import CampfireWeb.SignedInHelpers

  @david 127_326_141

  setup %{conn: conn} do
    {:ok, conn: sign_in(conn, @david)}
  end

  defp ids(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("id")

  test "full layout without a Turbo-Frame header, with both stream sources", %{conn: conn} do
    html = conn |> get("/users/me/sidebar") |> html_response(200)

    assert html =~ "<!DOCTYPE html>"
    assert html =~ ~s(<main id="main-content">)
    assert html =~ ~s(<meta name="csrf-token" content=")

    # The loadgen's exact regex (SPEC §1.3, T9).
    streams =
      Regex.scan(
        ~r/<turbo-cable-stream-source channel="([^"]+)" signed-stream-name="([^"]+)"/,
        html
      )

    assert [[_, "Turbo::StreamsChannel", rooms], [_, "Turbo::StreamsChannel", mine]] = streams
    assert {:ok, "rooms"} = Campfire.Signing.verify_stream_name(rooms)

    assert {:ok, name} = Campfire.Signing.verify_stream_name(mine |> String.replace("&#39;", "'"))
    assert name == Campfire.Signing.gid_param("User", @david) <> ":rooms"
  end

  test "frame layout with a Turbo-Frame header (T15)", %{conn: conn} do
    html =
      conn
      |> put_req_header("turbo-frame", "user_sidebar")
      |> get("/users/me/sidebar")
      |> html_response(200)

    refute html =~ "<!DOCTYPE html>"
    assert html =~ ~s(<meta name="csrf-token" content=")
    assert html =~ ~s(<turbo-frame data-turbo-permanent="true")

    assert length(
             Regex.scan(
               ~r/<turbo-cable-stream-source channel="Turbo::StreamsChannel" signed-stream-name="/,
               html
             )
           ) == 2
  end

  test "rooms, order, unread and placeholders", %{conn: conn} do
    doc = conn |> get("/users/me/sidebar") |> html_response(200) |> LazyHTML.from_document()

    # Shared rooms by name; the invisible Archive is hidden.
    assert ids(doc, "#shared_rooms a") == [
             "list_rooms_open_104393281",
             "list_rooms_closed_486777696",
             "list_rooms_closed_699448328",
             "list_rooms_closed_654632876",
             "list_rooms_open_201306877",
             "list_rooms_closed_699448326"
           ]

    assert ids(doc, "#shared_rooms a.unread") == ["list_rooms_closed_486777696"]

    # Directs by last activity.
    assert ids(doc, "#direct_rooms a") == [
             "list_rooms_direct_699448325",
             "list_rooms_direct_699448329",
             "list_rooms_direct_186869642"
           ]

    assert ids(doc, "#direct_rooms a.unread") == [
             "list_rooms_direct_699448325",
             "list_rooms_direct_699448329"
           ]

    kevin = LazyHTML.query(doc, "#list_rooms_direct_699448325")
    assert LazyHTML.text(kevin) =~ "Kevin"
    assert kevin |> LazyHTML.query("img") |> LazyHTML.attribute("width") == ["48"]

    group = LazyHTML.query(doc, "#list_rooms_direct_699448329")
    assert group |> LazyHTML.query(".avatar__group img") |> Enum.count() == 3
    assert LazyHTML.text(group) =~ "J, J, and K"

    assert doc
           |> LazyHTML.query("#list_rooms_direct_699448325")
           |> LazyHTML.attribute("data-sorted-list-number") ==
             ["1772460000000"]

    # Active users without a direct room with David.
    placeholders = LazyHTML.query(doc, "form.button_to[action^='/rooms/directs']")
    assert placeholders |> LazyHTML.attribute("action") |> length() == 3
    assert LazyHTML.text(placeholders) =~ "Bender"
    assert LazyHTML.text(placeholders) =~ "Lonely"

    assert LazyHTML.query(doc, "a.rooms__new-btn[href='/rooms/opens/new']") |> Enum.count() == 1

    assert LazyHTML.query(doc, "a.sidebar__tool[href='/users/me/profile'] img") |> Enum.count() ==
             1
  end
end
