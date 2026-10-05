defmodule Campfire.Repo do
  @moduledoc """
  The only connection that writes (pool of one; SQLite allows a single writer anyway, and
  serializing here avoids SQLITE_BUSY). Transactions are `BEGIN IMMEDIATE`.

  Reads belong on `Campfire.Repo.Replica` unless they must see the transaction in progress.
  """
  use Ecto.Repo, otp_app: :campfire, adapter: Ecto.Adapters.SQLite3

  @doc """
  Runs on connect (config `after_connect`): checkpoint the WAL every 4000 pages instead of 1000.

  The commit that crosses the threshold copies the WAL back into the database and fsyncs
  both, while holding the only write connection. That stall costs about the same at 4000 pages
  as at 1000 (~30 ms on an NVMe RAID1, dominated by the fsyncs), so checkpointing a quarter as
  often cuts the average COMMIT by ~60% for a WAL of up to 16 MB (bench/PERF.md). It is set
  here because exqlite's `custom_pragmas` run before `journal_mode=WAL`, which resets it.
  """
  def after_connect(conn), do: Exqlite.query!(conn, "PRAGMA wal_autocheckpoint = 4000")
end
