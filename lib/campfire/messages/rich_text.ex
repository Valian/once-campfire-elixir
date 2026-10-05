defmodule Campfire.Messages.RichText do
  @moduledoc "An Action Text body (`record_type` `Message`, `name` `body`). `body` is HTML."
  use Campfire.Schema

  schema "action_text_rich_texts" do
    field :record_type, :string, default: "Message"
    field :record_id, :integer
    field :name, :string, default: "body"
    field :body, :string
    timestamps()
  end
end
