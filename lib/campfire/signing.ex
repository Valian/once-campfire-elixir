defmodule Campfire.Signing do
  @moduledoc """
  Rails-compatible signed messages (`ActiveSupport::MessageVerifier`), keyed from
  `SECRET_KEY_BASE`, so tokens minted by the Rails app (avatar URLs in the seed, Turbo stream
  names) verify here and vice versa.

  A message is `{encoded data}--{hex HMAC of the encoded data}`. The HMAC key is
  `PBKDF2-HMAC-SHA256(secret_key_base, salt, 1000 iterations, 64 bytes)` (Rails' key generator),
  derived once per salt and kept in `:persistent_term`.

  The JSON envelope is `{"_rails":{"data":…,"exp":…,"pur":…}}` with keys in that order;
  `Jason.OrderedObject` keeps the order exact for nested data too.
  """

  alias Jason.OrderedObject

  @type digest :: :sha | :sha256
  @type encoding :: :strict | :url_safe | :url_safe_nopad

  ## Uses (SPEC §3)

  @doc "`record.signed_id(purpose:)`; for avatars the purpose is `user/avatar`."
  def signed_id(id, purpose) when is_integer(id) do
    id |> envelope(purpose) |> sign("active_record/signed_id", :sha256, :url_safe_nopad)
  end

  def verify_signed_id(token, purpose) when is_binary(token) do
    with {:ok, json} <- verify(token, "active_record/signed_id", :sha256, :url_safe_nopad),
         {:ok, id} when is_integer(id) <- open_envelope(json, purpose) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  @doc "Turbo's `signed_stream_name`: the stream name as a JSON string, no envelope."
  def signed_stream_name(name) when is_binary(name) do
    sign(Jason.encode!(name), "turbo/signed_stream_verifier_key", :sha256, :strict)
  end

  def verify_stream_name(signed) when is_binary(signed) do
    with {:ok, json} <- verify(signed, "turbo/signed_stream_verifier_key", :sha256, :strict),
         {:ok, name} when is_binary(name) <- Jason.decode(json) do
      {:ok, name}
    else
      _ -> :error
    end
  end

  @doc "A GlobalID URI: `gid(\"Rooms::Open\", 1)` is `\"gid://campfire/Rooms::Open/1\"`."
  def gid(class_name, id), do: "gid://campfire/#{class_name}/#{id}"

  @doc "`to_gid_param`: the GlobalID, base64 url-safe without padding."
  def gid_param(class_name, id), do: Base.url_encode64(gid(class_name, id), padding: false)

  @doc "`to_sgid(for: purpose)` with no expiry, as Action Text mention attachments use."
  def sgid(class_name, id, purpose \\ "attachable") do
    (gid(class_name, id) <> "?expires_in")
    |> envelope(purpose)
    |> sign("signed_global_ids", :sha, :url_safe)
  end

  ## Primitives

  @doc """
  The Rails purpose envelope as JSON. `data` is anything Jason encodes; use
  `Jason.OrderedObject` where Rails' key order isn't alphabetical. `expires_at` is a `DateTime`.
  """
  def envelope(data, purpose, expires_at \\ nil) do
    fields =
      [{"data", data}, expires_at && {"exp", format_expiry(expires_at)}, {"pur", purpose}]
      |> Enum.reject(&is_nil/1)

    Jason.encode!(OrderedObject.new([{"_rails", OrderedObject.new(fields)}]))
  end

  @doc "Unwraps an envelope, checking purpose and expiry. Returns the `data`."
  def open_envelope(json, purpose) do
    case Jason.decode(json) do
      {:ok, %{"_rails" => %{"data" => data, "pur" => ^purpose} = rails}} ->
        if expired?(rails["exp"]), do: :error, else: {:ok, data}

      _ ->
        :error
    end
  end

  @spec sign(binary, binary, digest, encoding) :: binary
  def sign(payload, salt, digest, encoding) do
    data = encode64(payload, encoding)
    data <> "--" <> hmac_hex(salt, digest, data)
  end

  @spec verify(binary, binary, digest, encoding) :: {:ok, binary} | :error
  def verify(message, salt, digest, encoding) do
    with {data, mac} <- split(message, digest),
         true <- Plug.Crypto.secure_compare(mac, hmac_hex(salt, digest, data)),
         {:ok, payload} <- decode64(data, encoding) do
      {:ok, payload}
    else
      _ -> :error
    end
  end

  @doc "The 64-byte key Rails derives for `salt`."
  def key(salt) do
    case :persistent_term.get({__MODULE__, salt}, nil) do
      nil ->
        secret = Application.fetch_env!(:campfire, :secret_key_base)
        key = :crypto.pbkdf2_hmac(:sha256, secret, salt, 1000, 64)
        :persistent_term.put({__MODULE__, salt}, key)
        key

      key ->
        key
    end
  end

  defp hmac_hex(salt, digest, data),
    do: :crypto.mac(:hmac, digest, key(salt), data) |> Base.encode16(case: :lower)

  # Like Rails, split where the fixed-length hex digest starts (the data may contain "--").
  defp split(message, digest) do
    mac_size = if digest == :sha, do: 40, else: 64
    data_size = byte_size(message) - mac_size - 2

    case message do
      <<data::binary-size(data_size), "--", mac::binary-size(mac_size)>> when data_size > 0 ->
        {data, mac}

      _ ->
        :error
    end
  end

  defp encode64(bin, :strict), do: Base.encode64(bin)
  defp encode64(bin, :url_safe), do: Base.url_encode64(bin)
  defp encode64(bin, :url_safe_nopad), do: Base.url_encode64(bin, padding: false)

  defp decode64(bin, :strict), do: Base.decode64(bin)
  defp decode64(bin, :url_safe), do: Base.url_decode64(bin)
  defp decode64(bin, :url_safe_nopad), do: Base.url_decode64(bin, padding: false)

  # Rails writes `exp` as ISO 8601 with milliseconds: "2046-01-01T00:00:00.000Z".
  defp format_expiry(%DateTime{microsecond: {usec, _}} = at) do
    DateTime.to_iso8601(%{at | microsecond: {div(usec, 1000) * 1000, 3}})
  end

  defp expired?(nil), do: false

  defp expired?(exp) do
    case DateTime.from_iso8601(exp) do
      {:ok, at, _} -> DateTime.compare(at, DateTime.utc_now()) != :gt
      _ -> true
    end
  end
end
