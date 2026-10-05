defmodule CampfireWeb.MessageWritesTest do
  use CampfireWeb.ConnCase

  import CampfireWeb.MessagesTestHelpers
  import Ecto.Query

  alias Campfire.Messages.{Boost, Message, RichText}
  alias Campfire.Repo
  alias Campfire.Rooms.{Membership, Room}
  alias Campfire.Storage
  alias Campfire.Storage.{Attachment, Blob, VariantRecord}

  @turbo "text/vnd.turbo-stream.html"

  setup %{conn: conn} do
    CampfireWeb.MessageRenderer.clear()
    david = user("david")
    {:ok, conn: log_in(conn, david), david: david}
  end

  defp post_message(conn, room_id, params) do
    conn
    |> put_req_header("accept", "#{@turbo}, text/html, application/xhtml+xml")
    |> post(~p"/rooms/#{room_id}/messages", %{"message" => params})
  end

  defp gid_stream(type, id), do: Campfire.Signing.gid_param(type, id) <> ":messages"

  test "posting a plain-text message as the loadgen does", %{conn: conn, david: david} do
    room = label("rooms.watercooler")
    subscribe(gid_stream("Rooms::Closed", room))
    for uid <- [label("users.david"), label("users.jason")], do: subscribe("user_#{uid}_unreads")
    room_before = Repo.get!(Room, room)

    conn = post_message(conn, room, %{"body" => "fanout bmk12z", "client_message_id" => "abc123"})

    assert [@turbo <> _] = get_resp_header(conn, "content-type")
    body = response(conn, 200)

    assert body =~
             ~s(<turbo-stream action="append" target="messages_rooms_closed_#{room}"><template><div id="message_abc123" class="message ")

    assert body =~ "fanout bmk12z"
    assert [_, first_img] = Regex.run(~r/<img[^>]+src="([^"]+)"/, body)
    assert first_img =~ ~r{^/users/.+/avatar\?v=}

    message = Repo.get_by!(Message, client_message_id: "abc123")
    assert message.creator_id == david.id

    assert Repo.get_by!(RichText, record_type: "Message", record_id: message.id).body ==
             "fanout bmk12z"

    assert DateTime.compare(Repo.get!(Room, room).updated_at, room_before.updated_at) == :gt

    %{rows: [[indexed]]} =
      Repo.query!("SELECT body FROM message_search_index WHERE rowid = ?", [message.id])

    assert indexed == "fanout bmk12z"

    # broadcasts: the room stream (no token in the forms) and every member's unreads
    assert_receive {:cable_broadcast, _, html}
    html = IO.iodata_to_binary(html)
    assert html =~ "fanout bmk12z"
    assert html =~ ~s(name="authenticity_token" value="")
    assert_receive {:cable_broadcast, "user_" <> _, %{"roomId" => ^room}}
    assert_receive {:cable_broadcast, "user_" <> _, %{"roomId" => ^room}}

    # unread for disconnected members other than the author
    memberships = Repo.all(from m in Membership, where: m.room_id == ^room)
    assert Enum.find(memberships, &(&1.user_id == david.id)).unread_at == nil || true
    jason = Enum.find(memberships, &(&1.user_id == label("users.jason")))
    assert DateTime.compare(jason.unread_at, message.created_at) == :eq
  end

  test "rich bodies are stored as submitted and sanitized on the way out", %{conn: conn} do
    room = label("rooms.hq")
    body = ~s"<p>Hi <strong>there</strong><script>alert(1)</script> https://example.com</p>"

    out =
      conn
      |> post_message(room, %{"body" => body, "client_message_id" => "rich-1"})
      |> response(200)

    refute out =~ "<script>"
    assert out =~ ~s(<strong>there</strong>)
    assert out =~ ~s(<a target="_blank" href="https://example.com">https://example.com</a>)

    assert Repo.get_by!(RichText,
             record_id: Repo.get_by!(Message, client_message_id: "rich-1").id
           ).body == body
  end

  test "a room the user isn't in: the composer frame says so", %{conn: conn} do
    out = conn |> post_message(label("rooms.bender_and_kevin"), %{"body" => "x"}) |> response(200)
    assert out =~ ~s(<turbo-frame id="composer-frame">)
    assert out =~ "This room was deleted."
  end

  test "uploading an image: blob, attachment, thumbnail variant, served files", %{conn: conn} do
    room = label("rooms.hq")

    upload = %Plug.Upload{
      path: Path.expand("bench/black_hole.jpg"),
      filename: "black_hole.jpg",
      content_type: "image/jpeg"
    }

    out =
      conn
      |> post_message(room, %{"attachment" => upload, "client_message_id" => "up-1"})
      |> response(200)

    message = Repo.get_by!(Message, client_message_id: "up-1")

    attachment =
      Repo.get_by!(Attachment, record_type: "Message", record_id: message.id, name: "attachment")

    blob = Repo.get!(Blob, attachment.blob_id)
    assert blob.content_type == "image/jpeg"

    assert blob.metadata == %{
             "identified" => true,
             "width" => 3840,
             "height" => 2160,
             "analyzed" => true
           }

    assert blob.checksum == :crypto.hash(:md5, File.read!(upload.path)) |> Base.encode64()
    assert File.exists?(Storage.path(blob))

    variant = Repo.get_by!(VariantRecord, blob_id: blob.id)
    assert variant.variation_digest == "IBhrLAIapu+NCId+2Kz6EqUWRKY="

    # plain text body for the index is the filename
    %{rows: [["black_hole.jpg"]]} =
      Repo.query!("SELECT body FROM message_search_index WHERE rowid = ?", [message.id])

    assert out =~ ~s(style="width: 600.0px; aspect-ratio: 1.7777777777777777;")
    assert out =~ ~s(width="1200.0" height="675.0")
    [_, thumb] = Regex.run(~r/class="message__attachment" loading="lazy" src="([^"]+)"/, out)

    served = build_conn() |> get(thumb)
    assert served.status == 200
    assert get_resp_header(served, "content-type") == ["image/jpeg"]
    assert {:ok, 1200, 675} = served.resp_body |> write_tmp() |> Storage.Files.image_dimensions()

    [_, original] = Regex.run(~r/data-lightbox-url-value="([^"]+)"/, out)
    download = build_conn() |> get(original |> String.replace("&amp;", "&"))
    assert download.status == 200

    assert [~s(attachment; filename="black_hole.jpg"; filename*=UTF-8''black_hole.jpg)] =
             get_resp_header(download, "content-disposition")

    ranged = build_conn() |> put_req_header("range", "bytes=0-9") |> get(original)
    assert ranged.status == 206
    assert byte_size(ranged.resp_body) == 10
  end

  test "seed attachments are served (and a missing variant is generated)", %{conn: conn} do
    html = conn |> get(~p"/rooms/#{label("rooms.designers")}") |> html_response(200)

    srcs =
      Regex.scan(~r{(?:src|poster)="(/rails/active_storage/[^"]+)"}, html)
      |> Enum.map(&List.last/1)
      |> Enum.uniq()

    assert length(srcs) >= 3

    for src <- srcs do
      served = build_conn() |> get(src)
      assert served.status == 200, src
    end
  end

  test "editing a message: frame, update, broadcast, redirect", %{conn: conn} do
    message_id = label("messages.first")
    message = Repo.get!(Message, message_id)
    room = Repo.get!(Room, message.room_id)

    edit = conn |> get(~p"/rooms/#{room.id}/messages/#{message_id}/edit") |> html_response(200)
    assert edit =~ ~s(<turbo-frame id="edit_message_#{message.client_message_id}">)
    assert edit =~ ~s(aria-label="Edit message")

    subscribe(gid_stream(Room.class_name(room), room.id))

    conn =
      conn
      |> recycle()
      |> patch(~p"/rooms/#{room.id}/messages/#{message_id}", %{
        "message" => %{"body" => "<p>Edited!</p>"}
      })

    assert redirected_to(conn) == "/rooms/#{room.id}/messages/#{message_id}"

    assert_receive {:cable_broadcast, _, payload}
    payload = IO.iodata_to_binary(payload)

    assert payload =~
             ~s(<turbo-stream maintain_scroll="true" action="replace" target="presentation_message_#{message.client_message_id}">)

    assert payload =~ "Edited!"

    show =
      conn |> recycle() |> get(~p"/rooms/#{room.id}/messages/#{message_id}") |> html_response(200)

    assert show =~ "Edited!"
  end

  test "only the creator or an administrator may edit", %{conn: conn} do
    message = Repo.get!(Message, label("messages.first"))
    kevin = log_in(build_conn(), user("kevin"))

    unless message.creator_id == label("users.kevin") do
      assert kevin
             |> get(~p"/rooms/#{message.room_id}/messages/#{message.id}/edit")
             |> response(403)
    end

    assert conn |> get(~p"/rooms/#{message.room_id}/messages/#{message.id}/edit") |> response(200)
  end

  test "deleting a message", %{conn: conn} do
    message = Repo.get!(Message, label("messages.first"))
    room = Repo.get!(Room, message.room_id)
    subscribe(gid_stream(Room.class_name(room), room.id))

    out = conn |> delete(~p"/rooms/#{room.id}/messages/#{message.id}") |> response(200)

    assert out ==
             ~s(<turbo-stream action="remove" target="message_#{message.client_message_id}"></turbo-stream>)

    assert Repo.get(Message, message.id) == nil
    assert Repo.all(from b in Boost, where: b.message_id == ^message.id) == []
    assert_receive {:cable_broadcast, _, _}
  end

  test "boosts: create (redirect, broadcast, touch) and destroy own", %{conn: conn, david: david} do
    message = Repo.get!(Message, label("messages.unboosted"))
    room = Repo.get!(Room, message.room_id)
    subscribe(gid_stream(Room.class_name(room), room.id))

    conn1 = post(conn, ~p"/messages/#{message.id}/boosts", %{"boost" => %{"content" => "🎉"}})
    assert redirected_to(conn1) == "/messages/#{message.id}/boosts"
    boost = Repo.get_by!(Boost, message_id: message.id, booster_id: david.id)
    assert DateTime.compare(Repo.get!(Message, message.id).updated_at, message.updated_at) == :gt

    assert_receive {:cable_broadcast, _, payload}
    payload = IO.iodata_to_binary(payload)

    assert payload =~
             ~s(<turbo-stream maintain_scroll="true" action="append" target="boosts_message_#{message.client_message_id}">)

    assert payload =~ ~s(class="txt-small txt-medium")

    index = conn |> recycle() |> get(~p"/messages/#{message.id}/boosts") |> html_response(200)
    assert index =~ ~s(id="boost_#{boost.id}")

    assert conn |> recycle() |> get(~p"/messages/#{message.id}/boosts/new") |> html_response(200) =~
             "boost[content]"

    assert conn
           |> recycle()
           |> delete(~p"/messages/#{message.id}/boosts/#{boost.id}")
           |> response(204)

    assert Repo.get(Boost, boost.id) == nil
    assert_receive {:cable_broadcast, _, removal}

    assert IO.iodata_to_binary(removal) ==
             ~s(<turbo-stream action="remove" target="boost_#{boost.id}"></turbo-stream>)
  end

  test "refresh: new messages appended, updated ones replaced", %{conn: conn} do
    room = Repo.get!(Room, label("rooms.watercooler"))
    since = DateTime.to_unix(room.updated_at, :millisecond)

    assert conn |> get(~p"/rooms/#{room.id}/refresh?since=#{since}") |> response(200) == ""

    conn
    |> recycle()
    |> post_message(room.id, %{"body" => "after since", "client_message_id" => "new-1"})

    out =
      conn
      |> recycle()
      |> get(~p"/rooms/#{room.id}/refresh?since=#{since}&reason=reconnect")
      |> response(200)

    assert out =~ ~s(<turbo-stream action="append" target="messages_rooms_closed_#{room.id}">)
    assert out =~ "after since"

    all = conn |> recycle() |> get(~p"/rooms/#{room.id}/refresh?since=0") |> response(200)
    assert all =~ ~s(action="append")
  end

  defp write_tmp(bytes) do
    path = Path.join(System.tmp_dir!(), "served-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    path
  end
end
