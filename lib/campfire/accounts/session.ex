defmodule Campfire.Accounts.Session do
  use Campfire.Schema

  schema "sessions" do
    field :token, :string, redact: true
    field :ip_address, :string
    field :user_agent, :string
    field :last_active_at, Timestamp
    belongs_to :user, Campfire.Accounts.User
    timestamps()
  end
end
