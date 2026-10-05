defmodule Campfire.RichTextCorpusTest do
  @moduledoc """
  Differential test against the Rails pipeline: `test/fixtures/rich_text_corpus.json.gz` is
  once-campfire-rust's corpus (658 stored bodies run through the reference app). Presentation
  is compared as normalized DOM (whitespace-only text dropped, whitespace collapsed, attributes
  sorted); plain text exactly.

  Bodies Rails raises on (it then renders an empty presentation) are only checked for safety:
  we render what we can instead of blanking the message.
  """
  use ExUnit.Case, async: true

  alias Campfire.RichText
  alias Campfire.RichText.HTML

  # Known divergences: name => reason. Beyond these, two classes are skipped by shape (see
  # `divergent?/1`): bodies with foreign content (svg/math/template), where lexbor and gumbo build
  # different trees for HTML breaking out of it; and Rails' own escaping quirks (rails_autolink
  # inserting links inside attribute values; Loofah passing `%20javascript:` hrefs).
  @nested_anchor "nested <a>: Rails' serialize-and-reparse splits nested anchors; we keep the tree"
  @divergent %{
    "attachment gallery" => "galleries aren't produced by Campfire's composer",
    "attachment gallery of missing" => "galleries aren't produced by Campfire's composer",
    "remote image" => "Rails' reparse moves the figure out of its <p>; we keep it inside",
    "xss name attribute" => "`name` is dropped on purpose (DOM clobbering)",
    "trix figure attachment json comment" => "Ruby's JSON parser accepts /* comments */",
    "fuzz 7" => "whitespace from a parse difference",
    "fuzz 212" => @nested_anchor,
    "fuzz 234" => "parse difference (`<x@y]]>` tags)",
    "fuzz 350" => @nested_anchor,
    "fuzz 384" => @nested_anchor
  }

  @corpus "test/fixtures/rich_text_corpus.json.gz"
          |> File.read!()
          |> :zlib.gunzip()
          |> Jason.decode!()

  setup_all do
    users =
      Map.new(@corpus["users"], fn u ->
        {u["id"],
         %{
           id: u["id"],
           name: u["name"],
           title: u["title"],
           path: u["user_path"],
           avatar: u["avatar_path"],
           sgid: u["attachable_sgid"]
         }}
      end)

    {:ok, users: users}
  end

  defp ctx(users, host) do
    %{
      users: users,
      host: host,
      mention: fn u ->
        [
          {"span", [{"class", "mention"}, {"sgid", u.sgid}],
           [
             {"a",
              [
                {"title", u.title},
                {"class", "btn avatar"},
                {"data-turbo-frame", "_top"},
                {"href", u.path}
              ],
              [
                {"img",
                 [{"aria-hidden", "true"}, {"src", u.avatar}, {"width", "48"}, {"height", "48"}],
                 []}
              ]},
             " " <> u.name
           ]}
        ]
      end
    }
  end

  defp cases(filter) do
    for c <- @corpus["cases"], filter.(c), not divergent?(c), do: c
  end

  defp divergent?(c) do
    rails = c["presentation"]["ok"] || ""

    Map.has_key?(@divergent, c["name"]) or Regex.match?(~r/<(svg|math|template)\b/i, c["body"]) or
      (String.contains?(rails, ["<a target=\"_blank\" href=\"", "%20jav"]) and
         Regex.match?(~r/="[^"]*<a target="_blank"|%20jav/, rails))
  end

  test "most of the corpus is compared" do
    assert length(cases(fn _ -> true end)) >= 420
  end

  test "presentation matches Rails (normalized DOM)", %{users: users} do
    cases = cases(&(&1["presentation_raised"] == nil and Map.has_key?(&1["presentation"], "ok")))

    failures =
      for c <- cases,
          tree = RichText.parse(c["body"]),
          ours = tree |> RichText.presentation(ctx(users, c["host"])) |> IO.iodata_to_binary(),
          normalize(ours) != normalize(c["presentation"]["ok"]) do
        {c["name"], c["body"], ours, c["presentation"]["ok"]}
      end

    report(failures, length(cases), "presentation")
  end

  test "plain text matches Rails", %{users: users} do
    cases = cases(&Map.has_key?(&1["plain_text"], "ok"))

    failures =
      for c <- cases,
          ours = c["body"] |> RichText.parse() |> RichText.plain_text(ctx(users, c["host"])),
          ours != c["plain_text"]["ok"] do
        {c["name"], c["body"], ours, c["plain_text"]["ok"]}
      end

    report(failures, length(cases), "plain text")
  end

  test "every body renders safely", %{users: users} do
    for c <- @corpus["cases"] do
      html =
        c["body"]
        |> RichText.parse()
        |> RichText.presentation(ctx(users, c["host"]))
        |> IO.iodata_to_binary()

      tree = HTML.parse(html)

      for {tag, attrs, _} <- HTML.find_all(tree, fn _ -> true end) do
        refute tag in ~w(script style iframe object embed form input button svg math template),
               "#{c["name"]}: <#{tag}>"

        for {name, value} <- attrs do
          refute String.starts_with?(name, "on"), "#{c["name"]}: #{name}"

          if name in ~w(href src) do
            cleaned = value |> String.replace(~r/[\x00-\x20]/, "") |> String.downcase()

            refute String.starts_with?(cleaned, ["javascript:", "vbscript:", "data:text/html"]),
                   "#{c["name"]}: #{value}"
          end
        end
      end
    end
  end

  defp report([], _total, _what), do: :ok

  defp report(failures, total, what) do
    sample =
      failures
      |> Enum.take(String.to_integer(System.get_env("CORPUS_SHOW", "8")))
      |> Enum.map_join("\n\n", fn {name, body, ours, rails} ->
        {ours, rails} =
          {inspect(normalize(ours), limit: :infinity),
           inspect(normalize(rails), limit: :infinity)}

        at = max(String.length(common_prefix(ours, rails)) - 60, 0)

        "#{name}\n  body:  #{inspect(body)}\n  ours:  …#{String.slice(ours, at, 400)}\n  rails: …#{String.slice(rails, at, 400)}"
      end)

    flunk("#{length(failures)}/#{total} #{what} cases differ:\n\n#{sample}")
  end

  defp common_prefix(a, b) do
    a
    |> String.graphemes()
    |> Enum.zip(String.graphemes(b))
    |> Enum.take_while(fn {x, y} -> x == y end)
    |> Enum.map_join(&elem(&1, 0))
  end

  defp normalize(html) when is_binary(html), do: html |> HTML.parse() |> normalize()

  defp normalize(tree) when is_list(tree) do
    tree
    |> Enum.flat_map(fn
      text when is_binary(text) ->
        case text |> String.split() |> Enum.join(" ") do
          "" -> []
          collapsed -> [collapsed]
        end

      {:comment, _} ->
        []

      {tag, attrs, children} ->
        [{tag, Enum.sort(attrs), normalize(children)}]
    end)
    |> merge_text()
  end

  defp merge_text([a, b | rest]) when is_binary(a) and is_binary(b),
    do: merge_text([a <> " " <> b | rest])

  defp merge_text([a | rest]), do: [a | merge_text(rest)]
  defp merge_text([]), do: []
end
