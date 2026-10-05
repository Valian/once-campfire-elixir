defmodule Campfire.Repo.Replica do
  @moduledoc """
  Read-only connections to the same SQLite file, one per scheduler. Under WAL they read
  concurrently with the writer and see every committed write.

  In test this module isn't started: it reads through `Campfire.Repo` (see `config/test.exs`),
  so queries see the sandbox transaction.
  """
  use Ecto.Repo,
    otp_app: :campfire,
    adapter: Ecto.Adapters.SQLite3,
    read_only: true,
    default_dynamic_repo:
      Application.compile_env(:campfire, [__MODULE__, :default_dynamic_repo], __MODULE__)
end
