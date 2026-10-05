defmodule Campfire.DataCase do
  @moduledoc "Tests against the seed database; each test's writes are rolled back."
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Campfire.Repo

      import Ecto.Query
      import Campfire.DataCase
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Campfire.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc "A value from bench/seed/labels.json, e.g. `label(\"emails.david\")`."
  def label(key) do
    seed = System.get_env("SEED_DIR", "bench/seed")
    labels = :persistent_term.get({__MODULE__, :labels}, nil) || load_labels(seed)
    Map.fetch!(labels, key)
  end

  defp load_labels(seed) do
    labels = seed |> Path.join("labels.json") |> File.read!() |> Jason.decode!()
    :persistent_term.put({__MODULE__, :labels}, labels)
    labels
  end
end
