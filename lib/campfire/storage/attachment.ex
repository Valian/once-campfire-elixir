defmodule Campfire.Storage.Attachment do
  @moduledoc "Polymorphic join of a record (`record_type`, `record_id`, `name`) to a blob."
  use Campfire.Schema

  schema "active_storage_attachments" do
    field :name, :string
    field :record_type, :string
    field :record_id, :integer
    belongs_to :blob, Campfire.Storage.Blob
    timestamps(updated_at: false)
  end
end
