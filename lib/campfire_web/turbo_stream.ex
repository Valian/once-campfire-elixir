defmodule CampfireWeb.TurboStream do
  @moduledoc """
  `<turbo-stream>` elements as iodata (turbo-rails' tag builder): extra attributes before
  `action`, `remove` without a template.
  """
  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  def append(target, content, attrs \\ []), do: stream("append", target, content, attrs)
  def prepend(target, content, attrs \\ []), do: stream("prepend", target, content, attrs)
  def replace(target, content, attrs \\ []), do: stream("replace", target, content, attrs)

  def remove(target),
    do: [~s(<turbo-stream action="remove" target="), escape(target), ~s("></turbo-stream>)]

  defp stream(action, target, content, attrs) do
    [
      "<turbo-stream",
      Enum.map(attrs, fn {k, v} -> [" ", to_string(k), "=\"", escape(to_string(v)), "\""] end),
      ~s( action="),
      action,
      ~s(" target="),
      escape(target),
      ~s("><template>),
      content,
      "</template></turbo-stream>"
    ]
  end

  defp escape(value), do: value |> html_escape() |> safe_to_string()

  @doc "Sends a turbo-stream response."
  def send(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("text/vnd.turbo-stream.html")
    |> Plug.Conn.send_resp(200, body)
  end
end
