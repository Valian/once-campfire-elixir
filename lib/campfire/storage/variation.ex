defmodule Campfire.Storage.Variation do
  @moduledoc """
  Active Storage variations: the transformations of a variant, their digest (the
  `active_storage_variant_records.variation_digest` lookup key) and their signed URL key.

  Transformations are an ordered keyword list, `format` first, as Rails builds them:

      [format: "jpg", resize_to_limit: [1200, 800]]        # thumb of a .jpg (a string format)
      [format: {:sym, "webp"}, resize_to_limit: [512, 512]] # avatar square (a symbol format)

  The digest is `Base64(SHA1(Marshal.dump(transformations)))`, so a symbol and a string spell
  different digests (SPEC §2.4, T12). The URL key only carries JSON, where both are strings;
  `digests/1` gives both spellings for lookups.
  """
  alias Campfire.Signing
  alias Jason.OrderedObject

  import Bitwise, only: [&&&: 2, >>>: 2]

  @type value :: binary | {:sym, binary} | [integer] | integer | nil
  @type t :: [{atom, value}]

  @doc "The variation digest Rails stores for these transformations."
  @spec digest(t) :: binary
  def digest(transformations),
    do: :crypto.hash(:sha, marshal(transformations)) |> Base.encode64()

  @doc "Digests for both spellings of the format (as given first), for lookups by URL key."
  def digests(transformations) do
    other =
      Enum.map(transformations, fn
        {:format, {:sym, f}} -> {:format, f}
        {:format, f} when is_binary(f) -> {:format, {:sym, f}}
        pair -> pair
      end)

    Enum.uniq([digest(transformations), digest(other)])
  end

  @doc "The signed variation key used in representation URLs."
  def key(transformations) do
    data =
      OrderedObject.new(
        Enum.map(transformations, fn {k, v} -> {Atom.to_string(k), json_value(v)} end)
      )

    data |> Signing.envelope("variation") |> Signing.sign("ActiveStorage", :sha, :strict)
  end

  @doc "Decodes a signed variation key into transformations (formats as strings)."
  @spec decode_key(binary) :: {:ok, t} | :error
  def decode_key(key) do
    with {:ok, json} <- Signing.verify(key, "ActiveStorage", :sha, :strict),
         {:ok, %{"_rails" => %{"data" => data, "pur" => "variation"}}} <- Jason.decode(json),
         {:ok, ordered} <- Jason.decode(json, objects: :ordered_objects),
         %OrderedObject{values: values} <- ordered["_rails"]["data"],
         true <- is_map(data),
         {:ok, transformations} <- known_keys(values) do
      {:ok, transformations}
    else
      _ -> :error
    end
  end

  @known %{"format" => :format, "resize_to_limit" => :resize_to_limit}

  defp known_keys(values) do
    Enum.reduce_while(values, {:ok, []}, fn {k, v}, {:ok, acc} ->
      case @known[k] do
        nil -> {:halt, :error}
        key -> {:cont, {:ok, acc ++ [{key, v}]}}
      end
    end)
  end

  defp json_value({:sym, s}), do: s
  defp json_value(v), do: v

  ## Marshal (the subset variations use: a hash with symbol keys; string, symbol, integer,
  ## integer array and nil values)

  @doc false
  def marshal(transformations) do
    {body, _symbols} =
      Enum.reduce(transformations, {[], %{}}, fn {k, v}, {acc, symbols} ->
        {key, symbols} = symbol(Atom.to_string(k), symbols)
        {value, symbols} = value(v, symbols)
        {[acc, key, value], symbols}
      end)

    IO.iodata_to_binary([4, 8, ?{, long(length(transformations)), body])
  end

  defp value({:sym, s}, symbols), do: symbol(s, symbols)

  defp value(s, symbols) when is_binary(s) do
    {e, symbols} = symbol("E", symbols)
    {[?I, ?", long(byte_size(s)), s, long(1), e, ?T], symbols}
  end

  defp value(nil, symbols), do: {"0", symbols}
  defp value(i, symbols) when is_integer(i), do: {[?i, long(i)], symbols}

  defp value(list, symbols) when is_list(list) do
    {items, symbols} = Enum.map_reduce(list, symbols, &value/2)
    {[?[, long(length(list)), items], symbols}
  end

  defp symbol(name, symbols) do
    case symbols do
      %{^name => index} -> {[?;, long(index)], symbols}
      _ -> {[?:, long(byte_size(name)), name], Map.put(symbols, name, map_size(symbols))}
    end
  end

  # Ruby's w_long
  defp long(0), do: <<0>>
  defp long(n) when n > 0 and n < 123, do: <<n + 5>>
  defp long(n) when n < 0 and n > -124, do: <<n - 5 &&& 0xFF>>

  defp long(n) when n >= -0x40000000 and n < 0x40000000 do
    bytes = little_endian(n, [])
    count = length(bytes)
    [if(n > 0, do: count, else: 256 - count) | bytes] |> :erlang.list_to_binary()
  end

  defp little_endian(n, acc) do
    byte = n &&& 0xFF
    rest = n >>> 8
    acc = [byte | acc]
    if rest == 0 or rest == -1, do: Enum.reverse(acc), else: little_endian(rest, acc)
  end
end
