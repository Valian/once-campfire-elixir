defmodule CampfireWeb.CableClient do
  @moduledoc """
  A minimal RFC 6455 client over `:gen_tcp` for cable tests: handshake with arbitrary headers,
  masked text frames out, unfragmented frames in. Buffered bytes live in the process
  dictionary, so a client is just its socket and calls needn't thread state.
  """

  @doc "Upgrades `GET /cable`. `{:ok, socket, status, headers}`; the socket is open only on 101."
  def connect(port, headers) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw])

    request = [
      "GET /cable HTTP/1.1\r\n",
      "Host: 127.0.0.1:#{port}\r\n",
      "Upgrade: websocket\r\nConnection: Upgrade\r\n",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n",
      for({k, v} <- headers, do: [k, ": ", v, "\r\n"]),
      "\r\n"
    ]

    :ok = :gen_tcp.send(socket, request)
    {status, headers, rest} = read_head(socket, "")
    Process.put({__MODULE__, socket}, rest)
    {:ok, socket, status, headers}
  end

  def send_json(socket, map), do: :gen_tcp.send(socket, masked(Jason.encode!(map)))

  @doc "Sends a subscribe command; `identifier` is a map (encoded) or the exact string."
  def subscribe(socket, identifier) when is_map(identifier),
    do: subscribe(socket, Jason.encode!(identifier))

  def subscribe(socket, identifier),
    do: send_json(socket, %{command: "subscribe", identifier: identifier})

  @doc "The next frame: `{:text, decoded_json}` or `{:close, code}`."
  def recv(socket, timeout \\ 1000) do
    case recv_frame(socket, timeout) do
      {1, payload} -> {:text, Jason.decode!(payload)}
      {8, payload} -> {:close, close_code(payload)}
      {:error, reason} -> {:error, reason}
      _ -> recv(socket, timeout)
    end
  end

  @doc "The next text frame that isn't a ping."
  def recv_message(socket, timeout \\ 1000) do
    case recv(socket, timeout) do
      {:text, %{"type" => "ping"}} -> recv_message(socket, timeout)
      other -> other
    end
  end

  @doc "The next text frame's payload, undecoded."
  def recv_raw(socket, timeout \\ 1000) do
    case recv_frame(socket, timeout) do
      {1, payload} -> {:ok, payload}
      other -> {:error, other}
    end
  end

  def close(socket), do: :gen_tcp.close(socket)

  defp recv_frame(socket, timeout) do
    buffer = Process.get({__MODULE__, socket}, "")

    case parse_frame(buffer) do
      {:ok, opcode, payload, rest} ->
        Process.put({__MODULE__, socket}, rest)
        {opcode, payload}

      :more ->
        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} ->
            Process.put({__MODULE__, socket}, buffer <> data)
            recv_frame(socket, timeout)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp close_code(<<code::16, _::binary>>), do: code
  defp close_code(_), do: nil

  defp read_head(socket, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        [status_line | lines] = String.split(head, "\r\n")
        [_, status | _] = String.split(status_line, " ")

        headers =
          for line <- lines do
            [k, v] = String.split(line, ":", parts: 2)
            {String.downcase(k), String.trim(v)}
          end

        {String.to_integer(status), headers, rest}

      [_] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 2000)
        read_head(socket, acc <> data)
    end
  end

  defp parse_frame(
         <<_::4, opcode::4, 0::1, 127::7, len::64, payload::binary-size(len), rest::binary>>
       ),
       do: {:ok, opcode, payload, rest}

  defp parse_frame(
         <<_::4, opcode::4, 0::1, 126::7, len::16, payload::binary-size(len), rest::binary>>
       ),
       do: {:ok, opcode, payload, rest}

  defp parse_frame(<<_::4, opcode::4, 0::1, len::7, payload::binary-size(len), rest::binary>>)
       when len < 126,
       do: {:ok, opcode, payload, rest}

  defp parse_frame(_), do: :more

  defp masked(payload) do
    mask = <<0x37, 0xFA, 0x21, 0x3D>>
    len = byte_size(payload)

    length =
      cond do
        len < 126 -> <<1::1, len::7>>
        len < 65_536 -> <<1::1, 126::7, len::16>>
        true -> <<1::1, 127::7, len::64>>
      end

    stream = binary_part(:binary.copy(mask, div(len, 4) + 1), 0, len)
    [<<0x81>>, length, mask, :crypto.exor(payload, stream)]
  end
end
