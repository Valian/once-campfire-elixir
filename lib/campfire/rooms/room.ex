defmodule Campfire.Rooms.Room do
  @moduledoc """
  Rails STI: `type` is `Rooms::Open`, `Rooms::Closed` or `Rooms::Direct`. The class name leaks
  into dom ids (`rooms_closed_1`), global ids and edit paths (`/rooms/closeds/1/edit`).
  """
  use Campfire.Schema

  @types [open: "Rooms::Open", closed: "Rooms::Closed", direct: "Rooms::Direct"]

  schema "rooms" do
    field :type, Ecto.Enum, values: @types
    field :name, :string
    belongs_to :creator, Campfire.Accounts.User
    has_many :memberships, Campfire.Rooms.Membership
    has_many :users, through: [:memberships, :user]
    has_many :messages, Campfire.Messages.Message
    timestamps()
  end

  @doc "The STI class name, e.g. `\"Rooms::Closed\"`."
  def class_name(%__MODULE__{type: type}), do: Keyword.fetch!(@types, type)

  @doc "Rails `model_name.param_key`, the `dom_id` prefix: `\"rooms_closed\"`."
  def param_key(%__MODULE__{type: type}), do: "rooms_#{type}"

  @doc "Rails `model_name.route_key`: `\"closeds\"` as in `/rooms/closeds/:id/edit`."
  def route_key(%__MODULE__{type: type}), do: "#{type}s"

  def direct?(%__MODULE__{type: type}), do: type == :direct
end
