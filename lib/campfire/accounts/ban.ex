defmodule Campfire.Accounts.Ban do
  use Campfire.Schema

  schema "bans" do
    field :ip_address, :string
    belongs_to :user, Campfire.Accounts.User
    timestamps()
  end
end
