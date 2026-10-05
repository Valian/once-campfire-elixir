defmodule CampfireWeb.RoomsTest do
  use CampfireWeb.ConnCase

  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Rooms.{Membership, Room}
  alias CampfireWeb.Cable

  @david 127_326_141
  @jason 149_087_659
  @kevin 712_064_548
  @jz 773_523_953
  @lou 773_523_958

  @hq 201_306_877
  @designers 654_632_876
  @watercooler 486_777_696
  @david_and_jason 186_869_642

  setup %{conn: conn} do
    {:ok, conn: sign_in(conn, @david)}
  end

  defp member_ids(room_id),
    do:
      Repo.all(
        from m in Membership, where: m.room_id == ^room_id, select: m.user_id, order_by: m.user_id
      )

  defp active_user_ids,
    do:
      Repo.all(
        from u in Campfire.Accounts.User, where: u.status == :active, select: u.id, order_by: u.id
      )

  describe "open rooms" do
    test "new form lists everyone", %{conn: conn} do
      doc = conn |> get("/rooms/opens/new") |> html_response(200) |> LazyHTML.from_document()

      assert doc
             |> LazyHTML.query("form[action='/rooms/opens'] input#room_name")
             |> LazyHTML.attribute("value") == ["New room"]

      assert doc
             |> LazyHTML.query("a[href='/rooms/closeds/new'] input#room_type[checked]")
             |> Enum.count() == 1

      assert doc |> LazyHTML.query("[data-filter-target=list] li") |> Enum.count() ==
               length(active_user_ids())
    end

    test "create grants every active user and announces the room on `rooms`", %{conn: conn} do
      subscribe_stream("rooms")
      conn = post(conn, "/rooms/opens", %{"room" => %{"name" => "Lunch"}})

      room = Repo.one!(from r in Room, where: r.name == "Lunch")
      assert room.type == :open
      assert room.creator_id == @david
      assert redirected_to(conn) == "/rooms/#{room.id}"
      assert member_ids(room.id) == active_user_ids()

      assert_cable("rooms", payload)
      assert payload =~ ~s(<turbo-stream action="prepend" target="shared_rooms"><template>)
      assert payload =~ ~s(id="list_rooms_open_#{room.id}")
      assert payload =~ "Lunch"
    end

    test "update renames and broadcasts a replace", %{conn: conn} do
      subscribe_stream("rooms")
      conn = patch(conn, "/rooms/opens/#{@hq}", %{"room" => %{"name" => "Headquarters"}})
      assert redirected_to(conn) == "/rooms/#{@hq}"
      assert Repo.get!(Room, @hq).name == "Headquarters"
      assert_cable("rooms", payload)
      assert payload =~ ~s(<turbo-stream action="replace" target="list_rooms_open_#{@hq}">)
    end

    test "submitting a closed room here opens it to everyone", %{conn: conn} do
      patch(conn, "/rooms/opens/#{@designers}", %{"room" => %{"name" => "Designers"}})
      assert Repo.get!(Room, @designers).type == :open

      assert member_ids(@designers) ==
               Enum.uniq(Enum.sort(active_user_ids() ++ member_ids(@designers)))
    end

    test "direct rooms are out of reach", %{conn: conn} do
      conn = get(conn, "/rooms/opens/#{@david_and_jason}/edit")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :alert) == "Room not found or inaccessible"
    end

    test "only administrators and creators may update", %{conn: conn} do
      kevin = sign_in(conn, @kevin)
      assert patch(kevin, "/rooms/opens/#{@hq}", %{"room" => %{"name" => "x"}}).status == 403

      # …but members see the settings read-only.
      doc =
        kevin |> get("/rooms/opens/#{@hq}/edit") |> html_response(200) |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("input#room_name") |> Enum.count() == 0
      assert doc |> LazyHTML.query("h1") |> LazyHTML.text() =~ "HQ"
      assert doc |> LazyHTML.query("button[type=submit]") |> Enum.count() == 0
    end

    test "show redirects to the room", %{conn: conn} do
      assert redirected_to(get(conn, "/rooms/opens/#{@hq}")) == "/rooms/#{@hq}"
    end
  end

  describe "closed rooms" do
    test "new form: the creator is fixed, others are switches", %{conn: conn} do
      doc = conn |> get("/rooms/closeds/new") |> html_response(200) |> LazyHTML.from_document()

      assert doc
             |> LazyHTML.query("input[type=hidden][name='user_ids[]']")
             |> LazyHTML.attribute("value") == ["#{@david}"]

      assert doc |> LazyHTML.query("input[type=checkbox][name='user_ids[]']") |> Enum.count() ==
               length(active_user_ids()) - 1
    end

    test "create grants the chosen users and tells each of them", %{conn: conn} do
      for id <- [@david, @jason, @kevin], do: subscribe_stream(Cable.user_rooms_stream(id))

      conn =
        post(conn, "/rooms/closeds", %{
          "room" => %{"name" => "Secret"},
          "user_ids" => ["#{@david}", "#{@jason}"]
        })

      room = Repo.one!(from r in Room, where: r.name == "Secret")
      assert room.type == :closed
      assert redirected_to(conn) == "/rooms/#{room.id}"
      assert member_ids(room.id) == Enum.sort([@david, @jason])

      david_stream = Cable.user_rooms_stream(@david)
      jason_stream = Cable.user_rooms_stream(@jason)
      assert_cable(^david_stream, payload)
      assert payload =~ ~s(target="shared_rooms")
      assert_cable(^jason_stream, _)
      refute_receive {:cable, _, _}, 10
    end

    test "edit marks members", %{conn: conn} do
      doc =
        conn
        |> get("/rooms/closeds/#{@designers}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      checked =
        doc
        |> LazyHTML.query("input[type=checkbox][name='user_ids[]'][checked]")
        |> LazyHTML.attribute("value")

      # Active members (banned Mallory is a member but not listed).
      assert Enum.sort(Enum.map(checked, &String.to_integer/1)) ==
               member_ids(@designers) -- [773_523_955]

      assert doc
             |> LazyHTML.query(
               "form[action='/rooms/#{@designers}'] input[name=_method][value=delete]"
             )
             |> Enum.count() == 1
    end

    test "update revises access: revoked members lose the room and are disconnected", %{
      conn: conn
    } do
      Phoenix.PubSub.subscribe(Campfire.PubSub, "user_connections:#{@kevin}")
      subscribe_stream(Cable.user_rooms_stream(@david))

      keep = member_ids(@designers) -- [@kevin]

      patch(conn, "/rooms/closeds/#{@designers}", %{
        "room" => %{"name" => "Design"},
        "user_ids" => Enum.map(keep, &to_string/1)
      })

      assert member_ids(@designers) == keep
      assert_receive {:disconnect, reconnect: true}
      david_stream = Cable.user_rooms_stream(@david)
      assert_cable(^david_stream, payload)

      assert payload =~
               ~s(<turbo-stream action="replace" target="list_rooms_closed_#{@designers}">)
    end

    test "submitting an open room here closes it", %{conn: conn} do
      patch(conn, "/rooms/closeds/#{@hq}", %{
        "room" => %{"name" => "HQ"},
        "user_ids" => ["#{@david}", "#{@jz}"]
      })

      assert Repo.get!(Room, @hq).type == :closed
      assert member_ids(@hq) == Enum.sort([@david, @jz])
    end
  end

  describe "direct rooms" do
    test "the new-ping frame", %{conn: conn} do
      html =
        conn
        |> put_req_header("turbo-frame", "direct_rooms_control")
        |> get("/rooms/directs/new")
        |> html_response(200)

      assert html =~ ~s(<turbo-frame id="direct_rooms_control" target="_top">)
      assert html =~ ~s(data-autocomplete-url-value="/autocompletable/users")
      assert html =~ ~s(<template id="autocompletable-user">)
    end

    test "an existing pair finds its room", %{conn: conn} do
      conn = post(conn, "/rooms/directs?user_ids[]=#{@jason}")
      assert redirected_to(conn) == "/rooms/#{@david_and_jason}"
    end

    test "a new set creates a room and shows it to each member", %{conn: conn} do
      subscribe_stream(Cable.user_rooms_stream(@lou))
      subscribe_stream(Cable.user_rooms_stream(@david))

      conn = post(conn, "/rooms/directs", %{"user_ids" => ["#{@lou}"]})
      "/rooms/" <> id = redirected_to(conn)
      room = Repo.get!(Room, String.to_integer(id))
      assert room.type == :direct
      assert member_ids(room.id) == Enum.sort([@david, @lou])
      assert Repo.get_by!(Membership, room_id: room.id, user_id: @lou).involvement == :everything

      lou_stream = Cable.user_rooms_stream(@lou)
      david_stream = Cable.user_rooms_stream(@david)
      assert_cable(^lou_stream, for_lou)
      assert_cable(^david_stream, for_david)
      assert for_lou =~ ~s(target="direct_rooms")
      # Each sees the other.
      assert for_lou =~ "David"
      assert for_david =~ "Lonely"

      # Asking again finds the same room.
      assert redirected_to(post(recycle(conn), "/rooms/directs", %{"user_ids" => ["#{@lou}"]})) ==
               "/rooms/#{room.id}"
    end

    test "edit lists the others; any member may delete", %{conn: conn} do
      doc =
        conn
        |> get("/rooms/directs/#{@david_and_jason}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert doc |> LazyHTML.query(".member strong") |> LazyHTML.text() == "Jason"
      assert doc |> LazyHTML.query("title") |> LazyHTML.text() == "Edit settings for Jason"

      subscribe_stream("rooms")
      conn = sign_in(conn, @jason) |> delete("/rooms/directs/#{@david_and_jason}")
      assert redirected_to(conn) == "/"
      refute Repo.get(Room, @david_and_jason)
      assert_cable("rooms", payload)

      assert payload ==
               ~s(<turbo-stream action="remove" target="list_rooms_direct_#{@david_and_jason}"></turbo-stream>)
    end
  end

  describe "rooms" do
    test "index goes to the newest room", %{conn: conn} do
      newest = Repo.one!(from r in Campfire.Rooms.for_user(@david), select: max(r.id))
      assert redirected_to(get(conn, "/rooms")) == "/rooms/#{newest}"
    end

    test "destroy removes the room and everything in it", %{conn: conn} do
      subscribe_stream("rooms")
      conn = delete(conn, "/rooms/#{@watercooler}")
      assert redirected_to(conn) == "/"
      refute Repo.get(Room, @watercooler)
      assert Repo.aggregate(from(m in "messages", where: m.room_id == @watercooler), :count) == 0
      assert member_ids(@watercooler) == []
      assert_cable("rooms", payload)
      assert payload =~ "list_rooms_closed_#{@watercooler}"

      %{rows: [[count]]} =
        Repo.query!("SELECT count(*) FROM message_search_index WHERE body MATCH 'coffee'")

      assert count == 1
    end

    test "only administrators and creators destroy", %{conn: conn} do
      assert delete(sign_in(conn, @kevin), "/rooms/#{@designers}").status == 403
    end
  end

  describe "involvement" do
    test "the bell frame cycles through involvements", %{conn: conn} do
      html =
        conn
        |> put_req_header("turbo-frame", "involvement_rooms_closed_#{@designers}")
        |> get("/rooms/#{@designers}/involvement")
        |> html_response(200)

      assert html =~ ~s(id="involvement_rooms_closed_#{@designers}")
      assert html =~ ~s(action="/rooms/#{@designers}/involvement?involvement=everything")
      assert html =~ ~s(class="btn mentions")
      assert html =~ "Notifying about @ mentions"

      direct = conn |> get("/rooms/#{@david_and_jason}/involvement") |> html_response(200)
      assert direct =~ ~s(action="/rooms/#{@david_and_jason}/involvement?involvement=nothing")
    end

    test "invisible hides the room from the sidebar, and back", %{conn: conn} do
      stream = Cable.user_rooms_stream(@david)
      subscribe_stream(stream)

      conn = put(conn, "/rooms/#{@designers}/involvement?involvement=invisible")
      assert redirected_to(conn) == "/rooms/#{@designers}/involvement"

      assert Repo.get_by!(Membership, room_id: @designers, user_id: @david).involvement ==
               :invisible

      assert_cable(^stream, removal)

      assert removal ==
               ~s(<turbo-stream action="remove" target="list_rooms_closed_#{@designers}"></turbo-stream>)

      put(recycle(conn), "/rooms/#{@designers}/involvement?involvement=mentions")
      assert_cable(^stream, payload)
      assert payload =~ ~s(<turbo-stream action="prepend" target="shared_rooms">)
    end

    test "not a member: 404; bad value: 422", %{conn: conn} do
      assert get(sign_in(conn, @lou), "/rooms/#{@designers}/involvement").status == 404
      assert put(conn, "/rooms/#{@designers}/involvement?involvement=loud").status == 422
    end
  end
end
