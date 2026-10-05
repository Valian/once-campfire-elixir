defmodule Campfire.RichText.HTML do
  @moduledoc """
  The tree the rich text pipeline works on (`LazyHTML.to_tree/1`'s shape: `{tag, attrs, children}`,
  text binaries, `{:comment, text}`) and its HTML5 serialization to iodata.
  """

  @type tree :: [html_node]
  @type html_node :: binary | {:comment, binary} | {binary, [{binary, binary}], tree}

  @void ~w(area base br col embed hr img input link meta param source track wbr)

  @doc "Parses an HTML fragment (body context, as Nokogiri's HTML5 fragment parser)."
  @spec parse(binary) :: tree
  def parse(""), do: []
  def parse(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  @doc "Serializes a tree."
  @spec to_iodata(tree) :: iodata
  def to_iodata(tree) when is_list(tree), do: Enum.map(tree, &node_iodata/1)

  def to_binary(tree), do: tree |> to_iodata() |> IO.iodata_to_binary()

  defp node_iodata(text) when is_binary(text), do: escape_text(text)
  defp node_iodata({:comment, text}), do: ["<!--", text, "-->"]

  defp node_iodata({tag, attrs, children}) when tag in @void,
    do: ["<", tag, attrs_iodata(attrs), ">" | maybe_children(tag, children)]

  defp node_iodata({tag, attrs, children}),
    do: ["<", tag, attrs_iodata(attrs), ">", to_iodata(children), "</", tag, ">"]

  # A void element never has children in a parsed tree; one built by hand might.
  defp maybe_children(_tag, []), do: []
  defp maybe_children(_tag, children), do: to_iodata(children)

  defp attrs_iodata(attrs),
    do: Enum.map(attrs, fn {k, v} -> [" ", k, "=\"", escape_attr(v), "\""] end)

  @doc "Escapes text content as the HTML5 serializer does: `& < >` and no-break spaces."
  def escape_text(text) do
    if String.contains?(text, ["&", "<", ">", " "]) do
      text
      |> String.replace("&", "&amp;")
      |> String.replace(" ", "&nbsp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
    else
      text
    end
  end

  @doc "Escapes an attribute value. `<` and `>` too, unlike HTML5, so values never look like tags."
  def escape_attr(value) do
    if String.contains?(value, ["&", "\"", "<", ">", " "]) do
      value
      |> String.replace("&", "&amp;")
      |> String.replace(" ", "&nbsp;")
      |> String.replace("\"", "&quot;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
    else
      value
    end
  end

  @doc "Reverses `escape_text/1`."
  def unescape_text(text) do
    if String.contains?(text, "&") do
      Regex.replace(~r/&(amp|lt|gt|nbsp);/, text, fn
        _, "amp" -> "&"
        _, "lt" -> "<"
        _, "gt" -> ">"
        _, "nbsp" -> " "
      end)
    else
      text
    end
  end

  ## Tree helpers

  def attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  def put_attr(attrs, name, value), do: List.keystore(attrs, name, 0, {name, value})

  @doc "Concatenated text of the nodes."
  def text_content(tree) when is_list(tree),
    do: tree |> Enum.map(&text_content/1) |> IO.iodata_to_binary()

  def text_content(text) when is_binary(text), do: text
  def text_content({:comment, _}), do: ""
  def text_content({_, _, children}), do: text_content(children)

  @doc "Whether `pred` holds for any element in the tree (depth first)."
  def any_element?(tree, pred) do
    Enum.any?(tree, fn
      {tag, _, children} = el when is_binary(tag) ->
        pred.(el) or any_element?(children, pred)

      _ ->
        false
    end)
  end

  @doc "Every element matching `pred`, in document order."
  def find_all(tree, pred) do
    Enum.flat_map(tree, fn
      {tag, _, children} = el when is_binary(tag) ->
        if pred.(el), do: [el | find_all(children, pred)], else: find_all(children, pred)

      _ ->
        []
    end)
  end

  @doc "Ruby's `String#strip`: ASCII whitespace and NUL."
  def strip(string), do: Regex.replace(~r/\A[\x00\t\n\v\f\r ]+|[\x00\t\n\v\f\r ]+\z/, string, "")

  @doc "Ruby's `blank?` for strings."
  def blank?(nil), do: true
  def blank?(string), do: String.trim(string) == ""

  @doc "Ruby's `chomp(\"\")`: every trailing newline (`\\n`, `\\r\\n`)."
  def chomp_newlines(string), do: Regex.replace(~r/(\r?\n)+\z/, string, "")
end
