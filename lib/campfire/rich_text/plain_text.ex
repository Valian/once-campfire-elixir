defmodule Campfire.RichText.PlainText do
  @moduledoc "`ActionText::PlainTextConversion` over a tree whose attachments are already replaced."
  import Campfire.RichText.HTML, only: [chomp_newlines: 1, blank?: 1]

  def convert(tree), do: tree |> nodes([]) |> chomp_newlines()

  # `anc`: the tag names above the nodes, innermost first.
  defp nodes(tree, anc) do
    {texts, _} =
      Enum.map_reduce(tree, 0, fn
        {"li", _, children}, index -> {li(children, anc, index), index + 1}
        {_, _, _} = el, index -> {node_text(el, anc), index + 1}
        other, index -> {node_text(other, anc), index}
      end)

    IO.iodata_to_binary(texts)
  end

  defp node_text(text, _) when is_binary(text), do: chomp_newlines(text)
  defp node_text({:comment, _}, _), do: ""
  defp node_text({tag, _, _}, _) when tag in ~w(script style), do: ""

  defp node_text({tag, _, children}, anc) when tag in ~w(p h1),
    do: block(nodes(children, [tag | anc]))

  defp node_text({tag, _, children}, anc) when tag in ~w(ul ol) do
    text = block(nodes(children, [tag | anc]))
    if list_depth(anc) > 0, do: "\n" <> text, else: text
  end

  defp node_text({"br", _, _}, _), do: "\n"

  defp node_text({"div", _, children}, anc),
    do: chomp_newlines(nodes(children, ["div" | anc])) <> "\n"

  defp node_text({"figcaption", _, children}, anc),
    do: "[" <> chomp_newlines(nodes(children, ["figcaption" | anc])) <> "]"

  defp node_text({"blockquote", _, children}, anc) do
    text = block(nodes(children, ["blockquote" | anc]))

    if blank?(text) do
      "“”"
    else
      [_, lead, body, trail] = Regex.run(~r/\A(\s*)(.*?\S)(\s*)\z/s, text)
      lead <> "“" <> body <> "”" <> trail
    end
  end

  defp node_text({_, _, children}, anc), do: nodes(children, anc)

  # `index`: the li's position among its parent's element children (for `ol` numbering).
  defp li(children, anc, index) do
    bullet = if Enum.find(anc, &(&1 in ~w(ul ol))) == "ol", do: "#{index + 1}.", else: "•"
    depth = list_depth(anc)
    indentation = if depth > 1, do: String.duplicate("  ", depth - 1), else: ""
    "#{indentation}#{bullet} #{chomp_newlines(nodes(children, ["li" | anc]))}\n"
  end

  defp block(text), do: chomp_newlines(text) <> "\n\n"

  defp list_depth(anc), do: Enum.count(anc, &(&1 in ~w(ul ol)))
end
