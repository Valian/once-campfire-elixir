defmodule Campfire.RichText.Autolink do
  @moduledoc """
  rails_autolink's `auto_link(html, html: { target: "_blank" })` over a tree: bare URLs and email
  addresses in text (outside `<a>`) become links.

  Rails runs its regular expressions over the serialized HTML, so a text's `&`, `<`, `>` and
  no-break spaces are seen as entities (`&amp;` …), which decides where a URL or address ends.
  Each text node is matched in that escaped form too; links are only ever inserted between tags.
  """
  alias Campfire.RichText.HTML

  @url ~r/(?:((?i:ed2k|ftp|http|https|irc|mailto|news|gopher|nntp|telnet|webcal|xmpp|callto|feed|svn|urn|aim|rsync|tag|ssh|sftp|rtsp|afs|file):)\/\/|(?i:www)\.[a-zA-Z0-9_])[^ \t\r\n\x0B\f<\x{A0}"]+/u
  @email ~r/(?<![a-zA-Z0-9_.!#$%&'*\/=?^`{|}~+-])[a-zA-Z0-9_.!#$%+-]\.?[a-zA-Z0-9_.!#$%&'*\/=?^`{|}~+-]*@[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)+/
  @trailing ~r/[^\w\/\-=;]\z/u
  @brackets %{"]" => "[", ")" => "(", "}" => "{"}

  # Unwrapped elements and dropped comments leave text nodes side by side that Rails, matching
  # serialized HTML, sees as one text.
  def link(tree) do
    tree
    |> merge_text()
    |> Enum.flat_map(fn
      text when is_binary(text) -> link_text(text)
      {"a", _, _} = anchor -> [anchor]
      {tag, attrs, children} -> [{tag, attrs, link(children)}]
      other -> [other]
    end)
  end

  defp link_text(text) do
    escaped = HTML.escape_text(text)

    if Regex.match?(~r/\/\/|@|www\./i, escaped) do
      escaped
      |> split(@url, &url_link/1)
      |> Enum.flat_map(fn
        {:escaped, part} -> split(part, @email, &email_link/1)
        node -> [node]
      end)
      |> Enum.flat_map(fn
        {:escaped, ""} -> []
        {:escaped, part} -> [HTML.unescape_text(part)]
        node -> [node]
      end)
      |> merge_text()
    else
      [text]
    end
  end

  # Splits escaped text on matches of `regex`, mapping each match to nodes.
  defp split(escaped, regex, fun) do
    case Regex.split(regex, escaped, include_captures: true, trim: false) do
      [_] ->
        [{:escaped, escaped}]

      parts ->
        parts
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {part, i} when rem(i, 2) == 0 -> [{:escaped, part}]
          {match, _} -> fun.(match)
        end)
    end
  end

  defp url_link(match) do
    {href, punctuation} = trim_punctuation(match, [])

    {href, trailing_gt} =
      if String.ends_with?(href, "&gt;"),
        do: {String.replace_suffix(href, "&gt;", ""), "&gt;"},
        else: {href, ""}

    text = HTML.unescape_text(href)
    scheme? = Regex.match?(~r/\A[a-z][a-z0-9]*:\/\//i, href)
    target = if scheme?, do: text, else: "http://" <> text

    [
      {"a", [{"target", "_blank"}, {"href", target}], [text]},
      {:escaped, Enum.join(punctuation) <> trailing_gt}
    ]
  end

  # Strip trailing punctuation, but keep a closing bracket the URL opened.
  defp trim_punctuation(href, punctuation) do
    case Regex.run(@trailing, href) do
      [char] ->
        href = String.replace_suffix(href, char, "")
        opening = @brackets[char]

        if opening && count(href, opening) > count(href, char),
          do: {href <> char, punctuation},
          else: trim_punctuation(href, [char | punctuation])

      nil ->
        {href, punctuation}
    end
  end

  defp count(string, char), do: length(String.split(string, char)) - 1

  defp email_link(email) do
    text = HTML.unescape_text(email)

    href =
      "mailto:" <> (text |> URI.encode(&URI.char_unreserved?/1) |> String.replace("%40", "@"))

    [{"a", [{"target", "_blank"}, {"href", href}], [text]}]
  end

  defp merge_text([a, b | rest]) when is_binary(a) and is_binary(b),
    do: merge_text([a <> b | rest])

  defp merge_text([a | rest]), do: [a | merge_text(rest)]
  defp merge_text([]), do: []
end
