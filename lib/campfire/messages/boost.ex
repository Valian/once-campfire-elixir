defmodule Campfire.Messages.Boost do
  use Campfire.Schema

  schema "boosts" do
    field :content, :string
    belongs_to :message, Campfire.Messages.Message
    belongs_to :booster, Campfire.Accounts.User
    timestamps()
  end
end
