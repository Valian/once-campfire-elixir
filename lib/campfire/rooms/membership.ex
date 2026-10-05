defmodule Campfire.Rooms.Membership do
  use Campfire.Schema

  schema "memberships" do
    field :involvement, Ecto.Enum,
      values: [:invisible, :nothing, :mentions, :everything],
      default: :mentions

    field :unread_at, Timestamp
    field :connected_at, Timestamp
    field :connections, :integer, default: 0
    belongs_to :room, Campfire.Rooms.Room
    belongs_to :user, Campfire.Accounts.User
    timestamps()
  end
end
