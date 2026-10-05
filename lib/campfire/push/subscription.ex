defmodule Campfire.Push.Subscription do
  use Campfire.Schema

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh_key, :string
    field :auth_key, :string
    field :user_agent, :string
    belongs_to :user, Campfire.Accounts.User
    timestamps()
  end
end
