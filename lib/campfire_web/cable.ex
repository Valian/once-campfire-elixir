defmodule CampfireWeb.Cable do
  @moduledoc """
  Real time over the Action Cable wire protocol (`actioncable-v1-json`), the BEAM way: one
  `CampfireWeb.Cable.Socket` process per WebSocket, `Phoenix.PubSub` (local) for fan-out.

  `broadcast/2` encodes a payload **once**; every subscribed socket wraps the shared binary
  in its own pre-encoded identifier (`[prefix, payload, "}"]`) and writes it as iodata. No
  per-subscriber JSON work, no GenServer in the delivery path.

  Pieces: `Cable.Upgrade` (the `/cable` plug: origin, auth, subprotocol), `Cable.Socket`
  (the protocol), `Cable.Channels` (authorization, streams, actions), `Cable.Pinger` (one
  3 s ticker for all sockets). To drop a user's sockets (sign-out, membership removal) use
  `CampfireWeb.UserAuth.disconnect_cable/1`.
  """

  @pubsub Campfire.PubSub

  @doc """
  Broadcasts to everyone streaming `stream` (an unsigned stream name such as
  `"\#{room_gid}:messages"`, `"rooms"` or `"user_1_unreads"`).

  An iodata payload is turbo-stream HTML and goes out as a JSON string (as
  `Turbo::StreamsChannel` does); a map goes out as a JSON object. Fire-and-forget and local.
  """
  @spec broadcast(String.t(), iodata() | map()) :: :ok
  def broadcast(stream, payload) when is_binary(stream) do
    Phoenix.PubSub.local_broadcast(@pubsub, topic(stream), {:cable, stream, encode(payload)})
  end

  @doc """
  `broadcast/2` of one payload to several streams (e.g. every member's unreads), encoded once.
  """
  @spec broadcast_many([String.t()], iodata() | map()) :: :ok
  def broadcast_many(streams, payload) when is_list(streams) do
    json = encode(payload)

    Enum.each(streams, fn stream ->
      Phoenix.PubSub.local_broadcast(@pubsub, topic(stream), {:cable, stream, json})
    end)
  end

  @doc "The payload's JSON, as one binary that all recipients share."
  @spec encode(iodata() | map()) :: binary()
  def encode(payload) when is_map(payload), do: Jason.encode!(payload)
  def encode(html) when is_binary(html), do: Jason.encode!(html)
  def encode(html) when is_list(html), do: html |> IO.iodata_to_binary() |> Jason.encode!()

  @doc false
  def topic(stream), do: "cable:" <> stream

  @doc false
  def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  @doc false
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  ## Stream names (SPEC §11.3, §11.4), for producers and channels alike.

  @doc "`{room gid param}:messages`: message, boost and edit turbo streams of a room."
  def room_messages_stream(room), do: room_gid_param(room) <> ":messages"

  @doc "`rooms`: sidebar updates everyone gets (open rooms, destroyed rooms)."
  def rooms_stream, do: "rooms"

  @doc "`{user gid param}:rooms`: a user's private sidebar updates."
  def user_rooms_stream(user_id), do: Campfire.Signing.gid_param("User", user_id) <> ":rooms"

  def unreads_stream(user_id), do: "user_#{user_id}_unreads"
  def reads_stream(user_id), do: "user_#{user_id}_reads"

  @doc "`to_gid_param` of a `%Room{}`."
  def room_gid_param(%Campfire.Rooms.Room{id: id} = room),
    do: Campfire.Signing.gid_param(Campfire.Rooms.Room.class_name(room), id)
end
