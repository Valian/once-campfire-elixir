defmodule CampfireWeb.Cable do
  @moduledoc """
  STUB (messages branch): the cable agent's module replaces this at merge. Only the contract
  below is relied on.

  `broadcast(stream, payload)`: `stream` is the unsigned stream name (`"{room gid}:messages"`,
  `"user_{id}_unreads"`, …); `payload` is iodata (turbo-stream HTML, sent as a JSON string) or a
  map (sent as a JSON object). Fire-and-forget, local, cheap.
  """

  @spec broadcast(String.t(), iodata() | map()) :: :ok
  def broadcast(stream, payload) when is_binary(stream) do
    Phoenix.PubSub.local_broadcast(Campfire.PubSub, stream, {:cable_broadcast, stream, payload})
    :ok
  end
end
