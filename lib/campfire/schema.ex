defmodule Campfire.Schema do
  @moduledoc """
  `use Campfire.Schema` in every schema mapped onto the Rails tables: integer ids, Rails-style
  `created_at`/`updated_at` stored as Rails' text datetimes (see `Campfire.Schema.Timestamp`).
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      alias Campfire.Schema.Timestamp

      @timestamps_opts [type: Campfire.Schema.Timestamp, inserted_at: :created_at]
    end
  end
end
