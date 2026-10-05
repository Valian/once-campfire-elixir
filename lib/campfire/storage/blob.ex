defmodule Campfire.Storage.Blob do
  @moduledoc """
  An Active Storage blob. The file is at `{root}/{key[0,2]}/{key[2,4]}/{key}`; `metadata` is JSON
  text (`{"identified":true,"width":W,"height":H,"analyzed":true}`), `checksum` base64 MD5.
  """
  use Campfire.Schema

  schema "active_storage_blobs" do
    field :key, :string
    field :filename, :string
    field :content_type, :string
    field :metadata, :map, default: %{}
    field :service_name, :string, default: "local"
    field :byte_size, :integer
    field :checksum, :string
    timestamps(updated_at: false)
  end
end
