defmodule Campfire.Id do
  @moduledoc "Record ids from params: an integer, or the decimal string of one; anything else is `nil`."

  @spec parse(term) :: integer | nil
  def parse(id) when is_integer(id), do: id

  def parse(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  def parse(_), do: nil
end
