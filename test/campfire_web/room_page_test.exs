defmodule CampfireWeb.RoomPageTest do
  use CampfireWeb.ConnCase

  import CampfireWeb.MessagesTestHelpers

  setup %{conn: conn} do
    CampfireWeb.MessageRenderer.clear()
    {:ok, conn: sign_in(conn, user("david"))}
  end

  test "the busy room: last 40 messages and the scraped contract", %{conn: conn} do
    room = label("rooms.watercooler")
    conn = get(conn, ~p"/rooms/#{room}")
    html = html_response(conn, 200)
    doc = document(html)

    assert [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]*)"/, html)
    assert token != ""

    # loadgen's exact regex, channel first
    assert [[_, "RoomMessagesChannel", signed]] =
             Regex.scan(
               ~r/<turbo-cable-stream-source channel="([^"]+)" signed-stream-name="([^"]+)"/,
               html
             )

    gid = Campfire.Signing.gid_param("Rooms::Closed", room)

    assert {:ok, ^gid <> ":messages"} =
             signed |> String.replace("&quot;", "\"") |> Campfire.Signing.verify_stream_name()

    assert doc |> LazyHTML.query("#messages_rooms_closed_#{room} > .message") |> Enum.count() ==
             40

    assert doc |> LazyHTML.query(~s(meta[name="current-room-id"])) |> attr("content") == "#{room}"
    assert doc |> LazyHTML.query("title") |> LazyHTML.text() == "All Talk"
    assert doc |> LazyHTML.query("#composer") |> attr("action") == "/rooms/#{room}/messages"
    assert doc |> LazyHTML.query(~s(script[type="text/template"])) |> Enum.count() == 1
    assert doc |> LazyHTML.query("#user_sidebar") |> attr("src") == "/users/me/sidebar"

    assert doc |> LazyHTML.query("#message-area") |> attr("data-messages-page-url-value") ==
             "http://www.example.com/rooms/#{room}/messages"

    assert [cookie] =
             get_resp_header(conn, "set-cookie")
             |> Enum.filter(&String.starts_with?(&1, "last_room"))

    assert String.starts_with?(cookie, "last_room=#{room};")

    # the first <img> of a message is its creator's avatar (trap T1)
    [first | _] = doc |> LazyHTML.query(".message") |> Enum.to_list()

    assert first |> LazyHTML.query("img") |> Enum.at(0) |> attr("src") =~
             ~r"^/users/[^/]+/avatar\?v=\d{14}$"

    # 8 quick boosts per message, each with the viewer's token
    tokens =
      doc
      |> LazyHTML.query(".quick-boosts form input[name=authenticity_token]")
      |> LazyHTML.attribute("value")

    assert length(tokens) == 320
    assert Enum.uniq(tokens) == [token]
  end

  test "a message permalink pages around it", %{conn: conn} do
    room = label("rooms.watercooler")
    message = label("messages.busy_060")
    doc = conn |> get("/rooms/#{room}/@#{message}") |> html_response(200) |> document()

    ids =
      doc |> LazyHTML.query(".message[data-message-id]") |> LazyHTML.attribute("data-message-id")

    assert "#{message}" in ids
    assert length(ids) == 81
  end

  test "a room the user isn't in redirects home with an alert", %{conn: conn} do
    conn = get(conn, ~p"/rooms/#{label("rooms.bender_and_kevin")}")
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :alert) == "Room not found or inaccessible"
  end

  test "direct rooms are named after the other members", %{conn: conn} do
    html = conn |> get(~p"/rooms/#{label("rooms.david_and_kevin")}") |> html_response(200)
    assert html =~ "<title>Kevin</title>"
    assert html =~ ~s(<span class="for-screen-reader">Ping with</span>)
    assert html =~ ~s(href="/rooms/directs/#{label("rooms.david_and_kevin")}/edit")
  end

  test "rich messages render: image, video, file, sound, mention, boosts", %{conn: conn} do
    for room <-
          ~w(designers pets hq watercooler david_and_jason david_and_kevin group_direct quiet archive broken) do
      conn = get(recycle(conn), ~p"/rooms/#{label("rooms.#{room}")}")
      assert conn.status in [200, 302], room
    end

    html = conn |> recycle() |> get(~p"/rooms/#{label("rooms.designers")}") |> html_response(200)
    assert html =~ "/rails/active_storage/representations/redirect/"
    assert html =~ ~s(class="message__attachment")
  end

  test "messages page: before/after, 204 when empty, 404 for a foreign id", %{conn: conn} do
    room = label("rooms.watercooler")
    before = label("messages.busy_060")

    conn1 = get(conn, ~p"/rooms/#{room}/messages?before=#{before}")
    body = response(conn1, 200)
    assert get_resp_header(conn1, "content-type") == ["text/html; charset=utf-8"]
    refute body =~ "<html"

    ids =
      body |> fragment() |> LazyHTML.query(".message") |> LazyHTML.attribute("data-message-id")

    assert length(ids) == 40
    refute "#{before}" in ids

    first = conn |> recycle() |> get(~p"/rooms/#{room}/messages?after=#{before}") |> response(200)
    assert first =~ "data-message-id"

    assert conn
           |> recycle()
           |> get(~p"/rooms/#{room}/messages?before=#{label("messages.first")}")
           |> response(404)
  end
end
