defmodule Campfire.Messages.Message do
  @moduledoc """
  The body lives in `action_text_rich_texts`, a file in `active_storage_attachments`.
  `client_message_id` (not `id`) is the dom id key: `message_{client_message_id}`.
  """
  use Campfire.Schema

  schema "messages" do
    field :client_message_id, :string
    belongs_to :room, Campfire.Rooms.Room
    belongs_to :creator, Campfire.Accounts.User
    has_many :boosts, Campfire.Messages.Boost

    has_one :rich_text, Campfire.Messages.RichText,
      foreign_key: :record_id,
      where: [record_type: "Message", name: "body"]

    has_one :attachment, Campfire.Storage.Attachment,
      foreign_key: :record_id,
      where: [record_type: "Message", name: "attachment"]

    timestamps()
  end
end
