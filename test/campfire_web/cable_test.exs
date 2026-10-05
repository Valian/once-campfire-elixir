defmodule CampfireWeb.CableTest do
  # Over a real socket: Bandit serves the endpoint on a random port, the sandbox is shared.
  use CampfireWeb.ConnCase

  alias Campfire.{Accounts, Repo, Signing}
  alias Campfire.Accounts.User
  alias Campfire.Rooms.{Membership, Room}
  alias CampfireWeb.{Cable, CableClient}

  @not_davids_room 340_026_324

  setup do
    bandit =
      start_supervised!(
        {Bandit, plug: CampfireWeb.Endpoint, port: 0, ip: :loopback, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    david = Repo.get!(User, label("users.david"))
    session = Accounts.start_session!(david, user_agent: "test", ip_address: "127.0.0.1")

    signed_token =
      Plug.Crypto.sign(
        CampfireWeb.Endpoint.config(:secret_key_base),
        "session_token_cookie",
        session.token,
        keys: Plug.Keys
      )

    # Close David's sockets while the sandbox is still up: their terminate runs presence SQL.
    on_exit(fn -> close_sockets(david.id) end)

    room = Repo.get!(Room, label("rooms.watercooler"))
    %{port: port, cookie: "session_token=" <> signed_token, david: david, room: room}
  end

  defp headers(port, cookie, extra \\ []) do
    [
      {"Origin", "http://127.0.0.1:#{port}"},
      {"Cookie", cookie},
      {"Sec-WebSocket-Protocol", "actioncable-v1-json, actioncable-unsupported"}
    ] ++ extra
  end

  defp connect!(%{port: port, cookie: cookie}) do
    {:ok, client, 101, _} = CableClient.connect(port, headers(port, cookie))
    {:text, %{"type" => "welcome"}} = CableClient.recv(client)
    client
  end

  defp close_sockets(user_id) do
    topic = "user_connections:#{user_id}"
    refs = for {pid, _} <- Registry.lookup(Campfire.PubSub, topic), do: Process.monitor(pid)
    CampfireWeb.UserAuth.disconnect_cable(%User{id: user_id})
    for ref <- refs, do: assert_receive({:DOWN, ^ref, _, _, _}, 2000)
  end

  defp subscribe!(client, identifier) do
    :ok = CableClient.subscribe(client, identifier)
    CableClient.recv_message(client)
  end

  # Commands run in order: once a later subscribe is confirmed, the earlier ones are done.
  defp sync(client) do
    heartbeat = ~s({"channel":"HeartbeatChannel","n":#{System.unique_integer([:positive])}})
    assert confirmed?(subscribe!(client, heartbeat))
  end

  defp confirmed?({:text, %{"type" => "confirm_subscription"}}), do: true
  defp confirmed?(_), do: false

  defp signed(channel, name),
    do: %{"channel" => channel, "signed_stream_name" => Signing.signed_stream_name(name)}

  defp action(identifier, action),
    do: %{command: "message", identifier: identifier, data: Jason.encode!(%{action: action})}

  describe "handshake" do
    test "echoes the actioncable subprotocol, welcomes and pings", %{port: port, cookie: cookie} do
      {:ok, client, 101, resp} = CableClient.connect(port, headers(port, cookie))
      assert {"sec-websocket-protocol", "actioncable-v1-json"} in resp
      assert {:text, %{"type" => "welcome"}} = CableClient.recv(client)

      send(CampfireWeb.Cable.Pinger, :ping)
      assert {:text, %{"type" => "ping", "message" => at}} = CableClient.recv(client)
      assert_in_delta at, System.os_time(:second), 2
    end

    test "permessage-deflate is declined (broadcasts stay encode-once)", %{
      port: port,
      cookie: cookie
    } do
      ext = {"Sec-WebSocket-Extensions", "permessage-deflate; client_max_window_bits"}
      {:ok, _client, 101, resp} = CableClient.connect(port, headers(port, cookie, [ext]))

      refute List.keyfind(resp, "sec-websocket-extensions", 0)
    end

    test "another origin, or no upgrade, is a 404", %{port: port, cookie: cookie} do
      bad = [{"Origin", "http://evil.example"}, {"Cookie", cookie}]
      assert {:ok, _, 404, _} = CableClient.connect(port, bad)
      assert {:ok, _, 404, _} = CableClient.connect(port, [{"Cookie", cookie}])

      conn = build_conn() |> put_req_header("origin", "http://www.example.com")
      assert conn |> get("/cable") |> response(404)
    end

    test "no session: disconnect (unauthorized, no reconnect) and close", %{port: port} do
      {:ok, client, 101, _} = CableClient.connect(port, headers(port, "session_token=nope"))

      assert {:text, %{"type" => "disconnect", "reason" => "unauthorized", "reconnect" => false}} =
               CableClient.recv(client)

      assert {:close, 1000} = CableClient.recv(client)
    end

    test "a remote disconnect asks the client to reconnect", ctx do
      client = connect!(ctx)
      CampfireWeb.UserAuth.disconnect_cable(ctx.david)

      assert {:text, %{"type" => "disconnect", "reason" => "remote", "reconnect" => true}} =
               CableClient.recv_message(client)

      assert {:close, 1000} = CableClient.recv(client)
    end
  end

  describe "subscriptions" do
    test "the loadgen's six all confirm, identifiers echoed verbatim", ctx do
      client = connect!(ctx)
      %{room: room, david: david} = ctx

      identifiers = [
        ~s({"channel":"PresenceChannel","room_id":#{room.id}}),
        ~s({"channel":"UnreadRoomsChannel"}),
        ~s({"channel":"HeartbeatChannel"}),
        Jason.encode!(signed("RoomMessagesChannel", Cable.room_messages_stream(room))),
        Jason.encode!(signed("Turbo::StreamsChannel", "rooms")),
        Jason.encode!(signed("Turbo::StreamsChannel", Cable.user_rooms_stream(david.id)))
      ]

      for identifier <- identifiers, do: :ok = CableClient.subscribe(client, identifier)

      for identifier <- identifiers do
        assert {:text, frame} = CableClient.recv_message(client)
        assert frame == %{"identifier" => identifier, "type" => "confirm_subscription"}
      end
    end

    test "rejections", ctx do
      client = connect!(ctx)
      %{room: room} = ctx
      other = %Room{id: @not_davids_room, type: :direct}
      wrong_class = Signing.gid_param("Rooms::Open", room.id) <> ":messages"

      for identifier <- [
            # T10: room messages only through RoomMessagesChannel, and only for members.
            signed("Turbo::StreamsChannel", Cable.room_messages_stream(room)),
            signed("RoomMessagesChannel", Cable.room_messages_stream(other)),
            signed("RoomMessagesChannel", "rooms"),
            signed("RoomMessagesChannel", wrong_class),
            %{"channel" => "Turbo::StreamsChannel", "signed_stream_name" => "forged--00"},
            %{"channel" => "Turbo::StreamsChannel"},
            %{"channel" => "PresenceChannel", "room_id" => @not_davids_room},
            %{"channel" => "TypingNotificationsChannel", "room_id" => "nope"},
            %{"channel" => "RoomChannel"}
          ] do
        identifier = Jason.encode!(identifier)

        assert {:text, %{"identifier" => ^identifier, "type" => "reject_subscription"}} =
                 subscribe!(client, identifier)
      end
    end

    test "unknown channels and duplicate identifiers get no reply", ctx do
      client = connect!(ctx)
      heartbeat = ~s({"channel":"HeartbeatChannel"})

      assert confirmed?(subscribe!(client, heartbeat))
      :ok = CableClient.subscribe(client, heartbeat)
      :ok = CableClient.subscribe(client, ~s({"channel":"NoSuchChannel"}))
      :ok = CableClient.send_json(client, %{command: "subscribe", identifier: "not json"})
      :ok = CableClient.send_json(client, %{command: "bogus"})

      # Another key order is another identifier; the room id may be a string.
      reordered = ~s({"room_id":"#{ctx.room.id}","channel":"RoomChannel"})

      assert {:text, %{"identifier" => ^reordered, "type" => "confirm_subscription"}} =
               subscribe!(client, reordered)
    end
  end

  describe "broadcasts" do
    test "turbo-stream HTML goes out as a JSON string, maps as objects", ctx do
      client = connect!(ctx)
      %{room: room, david: david} = ctx

      # Extra keys and odd order: echoed byte for byte.
      messages =
        ~s({"zzz":1,"signed_stream_name":"#{Signing.signed_stream_name(Cable.room_messages_stream(room))}","channel":"RoomMessagesChannel"})

      assert confirmed?(subscribe!(client, messages))
      assert confirmed?(subscribe!(client, ~s({"channel":"UnreadRoomsChannel"})))

      html = [
        ~s(<turbo-stream action="append" target="x"><template>),
        "fanout bmk7z",
        "</template></turbo-stream>"
      ]

      Cable.broadcast("someone_elses_stream", %{nope: true})
      Cable.broadcast(Cable.room_messages_stream(room), html)
      Cable.broadcast(Cable.unreads_stream(david.id), %{roomId: room.id})

      assert {:ok, raw} = CableClient.recv_raw(client)
      assert raw =~ "fanout bmk7z"

      assert Jason.decode!(raw) == %{
               "identifier" => messages,
               "message" => IO.iodata_to_binary(html)
             }

      assert CableClient.recv_raw(client) ==
               {:ok,
                ~s({"identifier":"{\\"channel\\":\\"UnreadRoomsChannel\\"}","message":{"roomId":#{room.id}}})}
    end

    test "a stream followed twice: a frame per subscription; unsubscribe stops it", ctx do
      client = connect!(ctx)
      name = Signing.signed_stream_name("rooms")
      a = ~s({"channel":"Turbo::StreamsChannel","signed_stream_name":"#{name}"})
      b = ~s({"signed_stream_name":"#{name}","channel":"Turbo::StreamsChannel"})
      assert confirmed?(subscribe!(client, a))
      assert confirmed?(subscribe!(client, b))

      Cable.broadcast("rooms", "<turbo-stream></turbo-stream>")
      assert {:text, %{"identifier" => ^a}} = CableClient.recv_message(client)
      assert {:text, %{"identifier" => ^b}} = CableClient.recv_message(client)

      :ok = CableClient.send_json(client, %{command: "unsubscribe", identifier: a})
      sync(client)
      Cable.broadcast("rooms", "<turbo-stream></turbo-stream>")
      assert {:text, %{"identifier" => ^b}} = CableClient.recv_message(client)

      :ok = CableClient.send_json(client, %{command: "unsubscribe", identifier: b})
      sync(client)
      Cable.broadcast("rooms", "<turbo-stream></turbo-stream>")
      send(CampfireWeb.Cable.Pinger, :ping)
      assert {:text, %{"type" => "ping"}} = CableClient.recv(client)
    end

    test "broadcast_many: one payload to several streams", ctx do
      client = connect!(ctx)
      assert confirmed?(subscribe!(client, ~s({"channel":"UnreadRoomsChannel"})))

      streams = [Cable.unreads_stream(ctx.david.id), Cable.unreads_stream(-1)]
      Cable.broadcast_many(streams, %{roomId: 1})
      assert {:text, %{"message" => %{"roomId" => 1}}} = CableClient.recv_message(client)
    end

    test "typing notifications reach the room's typists", ctx do
      a = connect!(ctx)
      b = connect!(ctx)
      typing = ~s({"channel":"TypingNotificationsChannel","room_id":#{ctx.room.id}})
      assert confirmed?(subscribe!(a, typing))
      assert confirmed?(subscribe!(b, typing))

      :ok = CableClient.send_json(a, action(typing, "start"))
      expected = %{"action" => "start", "user" => %{"id" => ctx.david.id, "name" => "David"}}

      for client <- [a, b] do
        assert {:text, %{"identifier" => ^typing, "message" => ^expected}} =
                 CableClient.recv_message(client)
      end
    end
  end

  describe "presence" do
    defp membership(ctx),
      do: Repo.get_by!(Membership, room_id: ctx.room.id, user_id: ctx.david.id)

    test "subscribing marks the room read and connected; leaving disconnects", ctx do
      assert membership(ctx).unread_at
      client = connect!(ctx)
      reads = ~s({"channel":"ReadRoomsChannel"})
      assert confirmed?(subscribe!(client, reads))

      presence = ~s({"channel":"PresenceChannel","room_id":#{ctx.room.id}})
      assert confirmed?(subscribe!(client, presence))
      room_id = ctx.room.id
      assert {:text, %{"message" => %{"room_id" => ^room_id}}} = CableClient.recv_message(client)
      assert %{unread_at: nil, connections: 1, connected_at: %DateTime{}} = membership(ctx)
      :ok = CableClient.send_json(client, %{command: "unsubscribe", identifier: reads})

      other = connect!(ctx)
      assert confirmed?(subscribe!(other, presence))
      assert membership(ctx).connections == 2

      :ok = CableClient.send_json(other, action(presence, "absent"))
      :ok = CableClient.send_json(other, action(presence, "refresh"))
      sync(other)
      assert membership(ctx).connections == 1

      :ok = CableClient.send_json(client, %{command: "unsubscribe", identifier: presence})
      sync(client)
      assert %{connections: 0, connected_at: nil} = membership(ctx)
    end

    test "a closed socket counts as absent", ctx do
      client = connect!(ctx)
      presence = ~s({"channel":"PresenceChannel","room_id":#{ctx.room.id}})
      assert confirmed?(subscribe!(client, presence))
      assert membership(ctx).connections == 1

      topic = "user_connections:#{ctx.david.id}"
      [{pid, _}] = Registry.lookup(Campfire.PubSub, topic)
      ref = Process.monitor(pid)
      CableClient.close(client)
      assert_receive {:DOWN, ^ref, _, _, _}
      assert %{connections: 0, connected_at: nil} = membership(ctx)
    end
  end
end
