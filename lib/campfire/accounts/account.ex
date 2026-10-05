defmodule Campfire.Accounts.Account do
  @moduledoc "The single account row (`Account.first` in Rails)."
  use Campfire.Schema

  schema "accounts" do
    field :name, :string
    field :join_code, :string
    field :custom_styles, :string
    field :settings, :map
    field :singleton_guard, :integer, default: 0
    timestamps()
  end

  def restrict_room_creation_to_administrators?(%__MODULE__{settings: settings}),
    do: (settings || %{})["restrict_room_creation_to_administrators"] == true
end
