defmodule Campfire.Storage.VariantRecord do
  @moduledoc """
  A generated variant of `blob_id`. Its file is the blob attached to this record
  (`ActiveStorage::VariantRecord` / `image`). `variation_digest` is Marshal-based (SPEC §2.4).
  """
  use Campfire.Schema

  schema "active_storage_variant_records" do
    field :variation_digest, :string
    belongs_to :blob, Campfire.Storage.Blob

    has_one :image_attachment, Campfire.Storage.Attachment,
      foreign_key: :record_id,
      where: [record_type: "ActiveStorage::VariantRecord", name: "image"]
  end
end
