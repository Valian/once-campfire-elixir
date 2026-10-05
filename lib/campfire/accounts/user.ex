defmodule Campfire.Accounts.User do
  use Campfire.Schema

  schema "users" do
    field :name, :string
    field :email_address, :string
    field :password_digest, :string, redact: true
    field :role, Ecto.Enum, values: [member: 0, administrator: 1, bot: 2], default: :member
    field :status, Ecto.Enum, values: [active: 0, deactivated: 1, banned: 2], default: :active
    field :bio, :string
    field :bot_token, :string, redact: true

    has_many :memberships, Campfire.Rooms.Membership
    has_many :rooms, through: [:memberships, :room]
    has_many :sessions, Campfire.Accounts.Session

    has_one :avatar_attachment, Campfire.Storage.Attachment,
      foreign_key: :record_id,
      where: [record_type: "User", name: "avatar"]

    timestamps()
  end

  @doc ~S"Rails: `name.scan(/\b\w/).join`. Ruby's `\w` is ASCII-only, hence no `u` flag."
  def initials(%__MODULE__{name: name}) do
    ~r/\b\w/ |> Regex.scan(name) |> Enum.join()
  end

  @doc "Rails: `[name, bio].compact_blank.join(\" – \")` (en dash)."
  def title(%__MODULE__{name: name, bio: bio}) do
    [name, bio] |> Enum.reject(&(is_nil(&1) or String.trim(&1) == "")) |> Enum.join(" – ")
  end

  def administrator?(%__MODULE__{role: role}), do: role == :administrator
  def bot?(%__MODULE__{role: role}), do: role == :bot

  @doc "Rails `can_administer?(record)`: administrators, or the record's creator."
  def can_administer?(%__MODULE__{} = user, record \\ nil) do
    administrator?(user) or (record != nil and Map.get(record, :creator_id) == user.id)
  end
end
