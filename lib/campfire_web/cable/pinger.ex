defmodule CampfireWeb.Cable.Pinger do
  @moduledoc """
  Action Cable's heartbeat: every 3 s each socket gets `{"type":"ping","message":<unix s>}`.
  The browser client reconnects when it hasn't seen one for ~6 s. One ticker builds the frame
  once and broadcasts it, as Rails' server-wide heartbeat timer does.
  """
  use GenServer

  @interval 3_000
  @topic "cable_ping"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def topic, do: @topic

  @doc "The ping frame for `unix_seconds`."
  def frame(unix_seconds), do: ~s({"type":"ping","message":#{unix_seconds}})

  @impl true
  def init(_opts) do
    :timer.send_interval(@interval, :ping)
    {:ok, nil}
  end

  @impl true
  def handle_info(:ping, state) do
    frame = frame(System.os_time(:second))
    Phoenix.PubSub.local_broadcast(Campfire.PubSub, @topic, {:cable_ping, frame})
    {:noreply, state}
  end
end
