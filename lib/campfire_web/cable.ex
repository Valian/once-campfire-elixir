defmodule CampfireWeb.Cable do
  @moduledoc """
  STUB of the cable broadcast API (the real module is owned by the cable work and replaces this
  file at merge). Contract: `broadcast(stream, payload)` sends to every socket subscribed to the
  unsigned `stream`; `payload` is turbo-stream HTML (iodata) or a map (JSON message).
  Fire-and-forget.

  This stub publishes `{:cable_broadcast, stream, payload}` on `Campfire.PubSub` topic
  `"cable:" <> stream` so tests can observe broadcasts.
  """

  @spec broadcast(String.t(), iodata() | map()) :: :ok
  def broadcast(stream, payload) when is_binary(stream) do
    Phoenix.PubSub.local_broadcast(
      Campfire.PubSub,
      "cable:" <> stream,
      {:cable_broadcast, stream, payload}
    )
  end
end
