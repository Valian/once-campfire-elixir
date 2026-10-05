defmodule Campfire.Searches.Search do
  use Campfire.Schema

  schema "searches" do
    field :query, :string
    belongs_to :user, Campfire.Accounts.User
    timestamps()
  end
end
