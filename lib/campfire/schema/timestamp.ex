defmodule Campfire.Schema.Timestamp do
  @moduledoc """
  A UTC `DateTime` stored the way Rails writes `datetime(6)` columns to SQLite:
  `YYYY-MM-DD HH:MM:SS`, plus `.ffffff` only when the microseconds aren't zero.

  The format matters beyond looks: range filters (`created_at < ?`) compare TEXT, so every
  value we write or bind must use the same format as the rows Rails wrote. Loading also accepts
  SQLite's `STRFTIME('%Y-%m-%d %H:%M:%f')` (3 fractional digits) and ISO 8601 `T`/`Z` forms.

  (ecto_sqlite3's `datetime_type: :text_datetime` is global and drops microseconds, so it
  can't be used.)
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(%DateTime{} = dt), do: {:ok, normalize(DateTime.shift_zone!(dt, "Etc/UTC"))}
  def cast(%NaiveDateTime{} = ndt), do: {:ok, normalize(DateTime.from_naive!(ndt, "Etc/UTC"))}
  def cast(text) when is_binary(text), do: parse(text)
  def cast(_), do: :error

  @impl true
  def load(text) when is_binary(text), do: parse(text)
  def load(_), do: :error

  @impl true
  def dump(%DateTime{} = dt), do: {:ok, format(dt)}
  def dump(_), do: :error

  @impl true
  def equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  def equal?(a, b), do: a == b

  # Used by Ecto to autogenerate timestamps for custom types.
  def from_unix!(value, unit), do: normalize(DateTime.from_unix!(value, unit))

  @doc "The current time, truncated to microseconds."
  def utc_now, do: normalize(DateTime.utc_now())

  @doc "Rails' text form of `dt` (UTC), for raw SQL parameters."
  def format(%DateTime{microsecond: {usec, _}} = dt) do
    precision = if usec == 0, do: 0, else: 6

    %{DateTime.shift_zone!(dt, "Etc/UTC") | microsecond: {usec, precision}}
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp parse(text) do
    case NaiveDateTime.from_iso8601(text) do
      {:ok, ndt} -> {:ok, normalize(DateTime.from_naive!(ndt, "Etc/UTC"))}
      {:error, _} -> :error
    end
  end

  defp normalize(%DateTime{microsecond: {usec, _}} = dt), do: %{dt | microsecond: {usec, 6}}
end
