defmodule Campfire.RichText do
  @moduledoc """
  Message bodies (Action Text HTML as Lexxy or Trix submitted it, or plain text) to what the
  app shows: presentation HTML (SPEC §9.2), plain text (§9.4) and the editor's value.

  Everything works on one parsed tree (`parse/1`), so a body is parsed once per render:

      tree = RichText.parse(body)
      users = load(RichText.mentioned_user_ids(tree))
      ctx = %{users: users, host: "campfire.example", mention: &mention_partial/1}
      RichText.presentation(tree, ctx)   # iodata
      RichText.plain_text(tree, ctx)     # "Hey @David"

  `ctx.mention` renders a mentioned user (`users/_mention`) as tree nodes; the final scrub strips
  what Rails strips from it. `ctx.users` maps user ids to anything with a `:name`.

  The pipeline follows Rails' (remove solo unfurled link text → SanitizeTags → SanitizeAttributes
  → render attachments → auto_link's sanitize → auto_link) in a few passes over the tree instead
  of Rails' serialize-and-reparse rounds. The output is HTML-equivalent to Rails' (checked against
  the Rails-rendered corpus in `test/campfire/rich_text_corpus_test.exs`).
  """
  alias Campfire.RichText.{Attachments, Autolink, HTML, PlainText, Sanitizer}

  import HTML, only: [attr: 2]

  @attachment "action-text-attachment"
  @max_depth 4

  @doc "Parses and canonicalizes a stored body: attachments lose their inner HTML."
  @spec parse(binary | nil) :: HTML.tree()
  def parse(nil), do: []
  def parse(body), do: body |> HTML.strip() |> HTML.parse() |> canonicalize()

  defp canonicalize(tree) do
    Enum.flat_map(tree, fn
      {@attachment, attrs, _} ->
        [{@attachment, attrs, []}]

      {tag, attrs, children} ->
        if HTML.attr(attrs, "data-trix-attachment"),
          do: trix_attachment(attrs),
          else: [{tag, attrs, canonicalize(children)}]

      other ->
        [other]
    end)
  end

  @trix_attributes [
    {"sgid", "sgid"},
    {"contentType", "content-type"},
    {"url", "url"},
    {"href", "href"},
    {"filename", "filename"},
    {"filesize", "filesize"},
    {"width", "width"},
    {"height", "height"},
    {"previewable", "previewable"},
    {"presentation", "presentation"},
    {"caption", "caption"},
    {"content", "content"}
  ]

  # A Trix-era `<figure data-trix-attachment="{json}">` becomes an attachment (or nothing).
  defp trix_attachment(attrs) do
    merged =
      Enum.reduce(["data-trix-attachment", "data-trix-attributes"], %{}, fn name, acc ->
        case attr(attrs, name) && Jason.decode(attr(attrs, name)) do
          {:ok, %{} = map} -> Map.merge(acc, map)
          _ -> acc
        end
      end)

    attachment_attrs =
      for {trix, dashed} <- @trix_attributes,
          Map.has_key?(merged, trix),
          do: {dashed, ruby_to_s(merged[trix])}

    if attachment_attrs == [], do: [], else: [{@attachment, attachment_attrs, []}]
  end

  defp ruby_to_s(nil), do: ""
  defp ruby_to_s(value) when is_binary(value), do: value
  defp ruby_to_s(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp ruby_to_s(value), do: Jason.encode!(value)

  @doc "Ids of the users the body's mention attachments name (signatures not checked)."
  @spec mentioned_user_ids(HTML.tree()) :: [integer]
  def mentioned_user_ids(tree) do
    tree
    |> attachments()
    |> Enum.flat_map(fn {_, attrs, _} ->
      case attr(attrs, "sgid") && Attachments.sgid_user_id(attr(attrs, "sgid")) do
        id when is_integer(id) -> [id]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp attachments(tree), do: HTML.find_all(tree, &match?({@attachment, _, _}, &1))

  ## Plain text

  @doc "`message.body.to_plain_text`: the search index, emoji detection, `/play` commands."
  @spec plain_text(HTML.tree(), map) :: binary
  def plain_text(tree, ctx \\ %{users: %{}, host: nil}),
    do: tree |> plain_attachments(ctx) |> PlainText.convert()

  # A content attachment's own attachments stay unconverted (and so say nothing), as in Rails.
  defp plain_attachments(tree, ctx) do
    Enum.flat_map(tree, fn
      {@attachment, attrs, _} ->
        case Attachments.resolve(attrs, ctx) do
          {:content, nodes} -> canonicalize(nodes)
          attachable -> Attachments.plain_text(attachable, attrs)
        end

      {tag, attrs, children} ->
        [{tag, attrs, plain_attachments(children, ctx)}]

      other ->
        [other]
    end)
  end

  ## Presentation

  @doc "The message presentation: `<div class=\"lexxy-content\">…</div>`, as iodata."
  @spec presentation(HTML.tree(), map) :: iodata
  def presentation(tree, ctx) do
    html =
      tree
      |> remove_solo_unfurled_link_text(ctx)
      |> Sanitizer.drop_disallowed()
      |> Sanitizer.scrub(:content_filter)
      |> render_attachments(ctx, 0)
      |> Sanitizer.scrub(:auto_link)
      |> Autolink.link()
      |> HTML.to_iodata()

    [~s(<div class="lexxy-content">\n  ), html, "\n</div>\n"]
  end

  defp render_attachments(tree, ctx, depth) do
    Enum.flat_map(tree, fn
      {@attachment, attrs, _} ->
        case Attachments.resolve(attrs, ctx) do
          {:content, nodes} when depth < @max_depth ->
            nodes = nodes |> canonicalize() |> render_attachments(ctx, depth + 1)
            Attachments.render({:content, nodes}, ctx, attrs)

          {:content, _} ->
            []

          attachable ->
            Attachments.render(attachable, ctx, attrs)
        end

      {tag, attrs, children} ->
        [{tag, attrs, render_attachments(children, ctx, depth)}]

      other ->
        [other]
    end)
  end

  # ContentFilters::RemoveSoloUnfurledLinkText: a message that is only a link to what it unfurls
  # shows just the unfurl.
  defp remove_solo_unfurled_link_text(tree, ctx) do
    og = Attachments.opengraph_content_type()

    unfurls =
      HTML.find_all(tree, &match?({@attachment, _, _}, &1))
      |> Enum.filter(fn {_, a, _} -> attr(a, "content-type") == og end)

    with [{_, attrs, _} = unfurl] <- unfurls,
         {:opengraph, %{href: href}} when is_binary(href) <- Attachments.resolve(attrs, ctx),
         true <- normalize_tweet_url(href) == normalize_tweet_url(plain_text(tree, ctx)) do
      if HTML.any_element?(tree, &match?({"div", _, _}, &1)),
        do: replace_div_contents(tree, unfurl),
        else: drop_paragraphs_without_attachments(tree)
    else
      _ -> tree
    end
  end

  defp replace_div_contents(tree, unfurl) do
    Enum.map(tree, fn
      {"div", attrs, _} -> {"div", attrs, [unfurl]}
      {tag, attrs, children} -> {tag, attrs, replace_div_contents(children, unfurl)}
      other -> other
    end)
  end

  defp drop_paragraphs_without_attachments(tree) do
    Enum.flat_map(tree, fn
      {"p", _, children} = p ->
        if HTML.any_element?(children, &match?({@attachment, _, _}, &1)), do: [p], else: []

      {tag, attrs, children} ->
        [{tag, attrs, drop_paragraphs_without_attachments(children)}]

      other ->
        [other]
    end)
  end

  defp normalize_tweet_url(url) do
    if String.contains?(HTML.strip(url), ["x.com", "twitter.com"]) do
      uri = URI.parse(url)

      host =
        if uri.host && String.downcase(uri.host) == "x.com", do: "twitter.com", else: uri.host

      URI.to_string(%{uri | host: host, query: nil})
    else
      url
    end
  end

  ## Editing

  @doc """
  The value Lexxy's editor gets for a body (`RichTextHelper#editable_body` + Lexxy's attachment
  rendering): each attachment's `content-type` and `content` rebuilt from its attachable, the
  content JSON-encoded. `nil` when the body is blank.
  """
  @spec editable(HTML.tree(), map) :: binary | nil
  def editable(tree, ctx) do
    tree = editable_attachments(tree, ctx)
    html = HTML.to_binary(tree)
    if HTML.blank?(html), do: nil, else: html
  end

  defp editable_attachments(tree, ctx) do
    Enum.flat_map(tree, fn
      {@attachment, attrs, _} ->
        case Attachments.resolve(attrs, ctx) do
          {kind, _} = attachable when kind in [:user, :opengraph] ->
            content_type =
              if kind == :user,
                do: Attachments.mention_content_type(),
                else: Attachments.opengraph_content_type()

            content = attachable |> Attachments.render(ctx, attrs) |> HTML.to_binary()

            content =
              if HTML.blank?(attr(attrs, "url")), do: Jason.encode!(content), else: content

            attrs =
              attrs
              |> HTML.put_attr("content-type", content_type)
              |> HTML.put_attr("content", content)

            [{@attachment, attrs, []}]

          :missing ->
            []

          _ ->
            [{@attachment, attrs, []}]
        end

      {tag, attrs, children} ->
        [{tag, attrs, editable_attachments(children, ctx)}]

      other ->
        [other]
    end)
  end

  ## Predicates

  @emoji ~r/\A(\p{Emoji_Presentation}|\p{Extended_Pictographic}|\x{FE0F})+\z/u

  @doc "Whether the text is only emoji (class `message--emoji`; a boost's `txt-medium`)."
  def all_emoji?(text) when is_binary(text), do: Regex.match?(@emoji, text)
end
