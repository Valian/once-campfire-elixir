defmodule Campfire.Repo do
  use Ecto.Repo,
    otp_app: :campfire,
    adapter: Ecto.Adapters.SQLite3
end
