defmodule Campfire.Repo.Setup do
  @moduledoc """
  Boot-time database preparation, run synchronously after `Campfire.Repo` starts and before
  anything reads. We never migrate: the database is the Rails app's, schema unchanged.

    * an empty database gets the Rails schema (`priv/repo/structure.sql`);
    * indexes Rails lacks but our queries need are added (Rails ignores extra indexes);
    * presence left over from a previous run is cleared, as Rails does in `puma.rb`.
  """
  alias Campfire.Repo
  alias Campfire.Schema.Timestamp

  @indexes [
    # Every room page orders a room's messages by created_at.
    "CREATE INDEX IF NOT EXISTS index_messages_on_room_id_and_created_at ON messages (room_id, created_at)"
  ]

  def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :run, []}, restart: :temporary}

  def run do
    unless schema_loaded?(), do: load_structure()
    Enum.each(@indexes, &Repo.query!/1)
    reset_presence()
    :ignore
  end

  defp schema_loaded? do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'accounts'")

    count > 0
  end

  defp load_structure do
    Repo.transaction(fn ->
      Application.app_dir(:campfire, "priv/repo/structure.sql")
      |> File.read!()
      |> String.split(";\n")
      |> Enum.map(&strip_comments/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.each(&Repo.query!/1)
    end)
  end

  defp strip_comments(sql) do
    sql
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "--"))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp reset_presence do
    now = Timestamp.utc_now()
    cutoff = DateTime.add(now, -60, :second)

    Repo.query!(
      "UPDATE memberships SET connected_at = NULL, connections = 0, updated_at = ? WHERE connected_at >= ?",
      [Timestamp.format(now), Timestamp.format(cutoff)]
    )
  end
end
