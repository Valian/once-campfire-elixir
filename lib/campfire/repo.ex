defmodule Campfire.Repo do
  @moduledoc """
  The only connection that writes (pool of one; SQLite allows a single writer anyway, and
  serializing here avoids SQLITE_BUSY). Transactions are `BEGIN IMMEDIATE`.

  Reads belong on `Campfire.Repo.Replica` unless they must see the transaction in progress.
  """
  use Ecto.Repo, otp_app: :campfire, adapter: Ecto.Adapters.SQLite3
end
