defmodule CampfireWeb.Cable.Channels do
  @moduledoc """
  The channels of SPEC §11.3: who may subscribe, which streams a subscription follows, and the
  actions and callbacks it runs. Pure functions over a subscription map; the socket process
  owns the state and runs these in the order commands arrive.

  A subscription is `%{channel: name, streams: [stream], room_id: id | nil, membership_id: id | nil}`.
  """
  import Ecto.Query

  alias Campfire.Repo.Replica
  alias Campfire.Rooms.{Membership, Presence, Room}
  alias Campfire.Signing
  alias CampfireWeb.Cable

  @type user :: %{id: integer(), name: String.t()}
  @type subscription :: %{
          channel: String.t(),
          streams: [String.t()],
          room_id: integer() | nil,
          membership_id: integer() | nil
        }

  @room_channels %{
    "RoomChannel" => "room",
    "PresenceChannel" => "presence",
    "TypingNotificationsChannel" => "typing_notifications"
  }

  @doc """
  Authorizes a subscription from its parsed identifier. `:unknown` for a channel that doesn't
  exist (no reply, as Rails), `:reject` when it isn't allowed.
  """
  @spec subscribe(map(), user()) :: {:ok, subscription()} | :reject | :unknown
  def subscribe(%{"channel" => "HeartbeatChannel"}, _user), do: {:ok, sub("HeartbeatChannel", [])}

  def subscribe(%{"channel" => "UnreadRoomsChannel"}, user),
    do: {:ok, sub("UnreadRoomsChannel", [Cable.unreads_stream(user.id)])}

  def subscribe(%{"channel" => "ReadRoomsChannel"}, user),
    do: {:ok, sub("ReadRoomsChannel", [Cable.reads_stream(user.id)])}

  def subscribe(%{"channel" => channel} = params, user)
      when is_map_key(@room_channels, channel) do
    with {:ok, room_id} <- room_id(params["room_id"]),
         {membership_id, type} <- membership(user.id, room_id) do
      room = %Room{id: room_id, type: type}
      stream = Map.fetch!(@room_channels, channel) <> ":" <> Cable.room_gid_param(room)

      sub = %{sub(channel, [stream]) | room_id: room_id, membership_id: membership_id}
      if channel == "PresenceChannel", do: present(sub, user)
      {:ok, sub}
    else
      _ -> :reject
    end
  end

  # Room messages need membership; the name's signature alone isn't enough (T10).
  def subscribe(%{"channel" => "RoomMessagesChannel", "signed_stream_name" => signed}, user)
      when is_binary(signed) do
    with {:ok, name} <- Signing.verify_stream_name(signed),
         [gid_param, "messages"] <- String.split(name, ":", parts: 2),
         {:ok, room_id, type} <- room_from_gid(gid_param),
         {_membership_id, ^type} <- membership(user.id, room_id) do
      {:ok, sub("RoomMessagesChannel", [name])}
    else
      _ -> :reject
    end
  end

  # Stock Turbo channel: any verified name except room messages (RoomMessagesChannel's door).
  def subscribe(%{"channel" => "Turbo::StreamsChannel", "signed_stream_name" => signed}, _user)
      when is_binary(signed) do
    with {:ok, name} <- Signing.verify_stream_name(signed),
         false <- guarded_stream?(name) do
      {:ok, sub("Turbo::StreamsChannel", [name])}
    else
      _ -> :reject
    end
  end

  def subscribe(%{"channel" => channel}, _user)
      when channel in ["RoomMessagesChannel", "Turbo::StreamsChannel"],
      do: :reject

  def subscribe(_params, _user), do: :unknown

  @doc "Runs a channel action (`message` command). Unknown actions are ignored, as Rails logs them."
  @spec perform(subscription(), String.t(), user()) :: term()
  def perform(%{channel: "PresenceChannel"} = sub, "present", user), do: present(sub, user)

  def perform(%{channel: "PresenceChannel", membership_id: id}, "absent", _user),
    do: Presence.absent(id)

  def perform(%{channel: "PresenceChannel", membership_id: id}, "refresh", _user),
    do: Presence.refresh(id)

  def perform(%{channel: "TypingNotificationsChannel", streams: [stream]}, action, user)
      when action in ["start", "stop"] do
    Cable.broadcast(stream, %{action: action, user: %{id: user.id, name: user.name}})
  end

  def perform(_sub, _action, _user), do: :ok

  @doc "Unsubscribe callback (also run for every subscription when the socket closes)."
  @spec unsubscribed(subscription(), user()) :: term()
  def unsubscribed(%{channel: "PresenceChannel", membership_id: id}, _user),
    do: Presence.absent(id)

  def unsubscribed(_sub, _user), do: :ok

  @doc "Whether `Turbo::StreamsChannel` must turn the (verified) name away."
  def guarded_stream?(name), do: match?([_, "messages"], String.split(name, ":", parts: 2))

  defp present(%{room_id: room_id, membership_id: id}, user) do
    if Presence.present(id) == 1 do
      Cable.broadcast(Cable.reads_stream(user.id), %{room_id: room_id})
    end

    :ok
  end

  defp sub(channel, streams),
    do: %{channel: channel, streams: streams, room_id: nil, membership_id: nil}

  defp membership(user_id, room_id) do
    Replica.one(
      from m in Membership,
        join: r in Room,
        on: r.id == m.room_id,
        where: m.user_id == ^user_id and m.room_id == ^room_id,
        select: {m.id, r.type}
    )
  end

  defp room_id(id) when is_integer(id), do: {:ok, id}

  defp room_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp room_id(_), do: :error

  # GlobalID::Locator.locate(param, only: Room): a gid URI or its base64 param. The STI class
  # must match the room's (Rooms::Closed.find raises for an open room's id); checked by the
  # caller against the membership's room.
  defp room_from_gid(param) do
    uri =
      case Base.url_decode64(param, padding: false) do
        {:ok, "gid://" <> _ = uri} -> uri
        _ -> param
      end

    with "gid://campfire/Rooms::" <> rest <- uri,
         [type, id] <- String.split(rest, "/", parts: 2),
         {:ok, id} <- room_id(id),
         {:ok, type} <- room_type(type) do
      {:ok, id, type}
    else
      _ -> :error
    end
  end

  defp room_type("Open"), do: {:ok, :open}
  defp room_type("Closed"), do: {:ok, :closed}
  defp room_type("Direct"), do: {:ok, :direct}
  defp room_type(_), do: :error
end
