defmodule CampfireWeb.RateLimiter do
  @moduledoc """
  Fixed-window counters in ETS, e.g. Rails' `rate_limit to: 10, within: 3.minutes` on sign-in.
  Windows older than the current one are swept every minute.
  """
  use GenServer

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Counts a hit for `key`; `:ok` while within `limit` hits per `window_secs`."
  def hit(key, limit, window_secs) do
    window = div(System.system_time(:second), window_secs)

    count =
      :ets.update_counter(@table, {key, window_secs, window}, 1, {{key, window_secs, window}, 0})

    if count <= limit, do: :ok, else: :rate_limited
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)

    # Delete {{key, secs, window}, _} where window < div(now, secs).
    :ets.select_delete(@table, [
      {{{:_, :"$1", :"$2"}, :_}, [{:<, :"$2", {:div, now, :"$1"}}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
