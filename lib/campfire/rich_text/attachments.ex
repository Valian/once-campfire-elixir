defmodule Campfire.RichText.Attachments do
  @moduledoc """
  `<action-text-attachment>` nodes: what they attach (a mentioned user, an unfurled link, …) and
  each attachable's partial as a tree (SPEC §9.2 step 5) or as plain text (§9.4).

  Mentions are resolved from the SGID **without verifying its signature**, as Campfire does
  (`attachable_from_possibly_expired_sgid`): the GlobalID is read out of the payload and the user
  looked up among the ones the caller loaded (`ctx.users`).
  """
  alias Campfire.RichText.{HTML, Sanitizer}

  import HTML, only: [attr: 2, blank?: 1]

  @mention "application/vnd.campfire.mention"
  @opengraph "application/vnd.actiontext.opengraph-embed"
  @twitter_avatar "https://pbs.twimg.com/profile_images"
  # Rails matches the content type with an unescaped pattern, dots and all.
  @opengraph_re ~r/application\/vnd.actiontext.opengraph-embed/

  def opengraph_content_type, do: @opengraph
  def mention_content_type, do: @mention

  @type attachable ::
          {:user, map}
          | {:opengraph, map}
          | {:content, HTML.tree()}
          | {:remote_image, map}
          | {:remote_video, map}
          | :missing

  @doc "Resolves an attachment node's attributes to its attachable."
  @spec resolve([{binary, binary}], map) :: attachable
  def resolve(attrs, ctx) do
    content_type = attr(attrs, "content-type") || ""

    if Regex.match?(@opengraph_re, content_type) do
      {:opengraph, opengraph(attrs, ctx)}
    else
      case mentioned_user(attrs, ctx) do
        nil -> action_text_attachable(attrs, content_type)
        user -> {:user, user}
      end
    end
  end

  defp action_text_attachable(attrs, content_type) do
    content = if String.contains?(content_type, "html"), do: content_tree(attrs), else: []
    url = attr(attrs, "url")

    cond do
      content != [] ->
        {:content, content}

      url && Regex.match?(~r/^image(\/.+|$)/m, content_type) ->
        {:remote_image, %{url: url, width: attr(attrs, "width"), height: attr(attrs, "height")}}

      url && Regex.match?(~r/^video(\/.+|$)/m, content_type) ->
        {:remote_video, %{url: url, filename: attr(attrs, "filename")}}

      true ->
        :missing
    end
  end

  defp mentioned_user(attrs, ctx) do
    with sgid when is_binary(sgid) <- attr(attrs, "sgid"),
         id when is_integer(id) <- sgid_user_id(sgid) do
      Map.get(ctx.users, id)
    else
      _ -> nil
    end
  end

  # The `content` attribute, sanitized with Action Text's list, as a tree ([] if blank).
  defp content_tree(attrs) do
    case attr(attrs, "content") do
      nil ->
        []

      content ->
        tree = content |> HTML.strip() |> HTML.parse() |> Sanitizer.scrub(:action_text)
        if blank_tree?(tree), do: [], else: tree
    end
  end

  defp blank_tree?(tree), do: Enum.all?(tree, &(is_binary(&1) and blank?(&1)))

  @doc """
  The user id a mention SGID names (`gid://…/User/{id}`), without checking the signature:
  `_rails.data`, or Rails 7's Marshal-dumped `_rails.message`. `nil` if it names none.
  """
  def sgid_user_id(sgid) do
    with [message | _] <- sgid |> String.split("--") |> drop_trailing_empty(),
         {:ok, json} <- decode64(message),
         {:ok, %{"_rails" => %{} = rails}} <- Jason.decode(json),
         gid when is_binary(gid) <- gid_from(rails),
         [_, id] <- Regex.run(~r{\Agid://[^/]+/User/(\d+)(?:\?|\z)}, gid) do
      String.to_integer(id)
    else
      _ -> nil
    end
  end

  defp gid_from(%{"data" => data}) when is_binary(data), do: data

  defp gid_from(%{"message" => message}) when is_binary(message) do
    with {:ok, bytes} <- decode64(message),
         [gid] <- Regex.run(~r{gid://campfire/[^/]+/\d+}, bytes) do
      gid
    else
      _ -> nil
    end
  end

  defp gid_from(_), do: nil

  defp drop_trailing_empty(parts),
    do: parts |> Enum.reverse() |> Enum.drop_while(&(&1 == "")) |> Enum.reverse()

  defp decode64(message) do
    with :error <- Base.decode64(message),
         :error <- Base.url_decode64(message, padding: false),
         :error <- Base.url_decode64(message) do
      :error
    end
  end

  ## Opengraph embeds

  defp opengraph(attrs, ctx) do
    host = ctx.host || ""

    if blank?(attr(attrs, "filename")) do
      embed_from_content(attr(attrs, "content") || "", host)
    else
      %{
        href: web_url(attr(attrs, "href"), host),
        url: web_url(attr(attrs, "url"), host),
        filename: attr(attrs, "filename"),
        description: attr(attrs, "caption")
      }
    end
  end

  defp embed_from_content(content, host) do
    tree = content |> HTML.parse() |> Sanitizer.scrub(:action_text)
    title = tree |> HTML.find_all(&has_class?(&1, "og-embed__title")) |> List.first()
    link = title && title |> children() |> HTML.find_all(&tag?(&1, "a")) |> List.first()

    image =
      tree
      |> HTML.find_all(&has_class?(&1, "og-embed__image"))
      |> Enum.flat_map(&HTML.find_all(children(&1), fn el -> tag?(el, "img") end))
      |> List.first()

    description = tree |> HTML.find_all(&has_class?(&1, "og-embed__description")) |> List.first()

    %{
      href: web_url(link && attr(elem(link, 1), "href"), host),
      url: web_url(image && attr(elem(image, 1), "src"), host),
      filename: (link || title) && HTML.strip(HTML.text_content([link || title])),
      description: description && HTML.strip(HTML.text_content([description]))
    }
  end

  defp children({_, _, children}), do: children
  defp tag?({tag, _, _}, name), do: tag == name

  defp has_class?({_, attrs, _}, class) do
    case attr(attrs, "class") do
      nil -> false
      classes -> class in String.split(classes, [" ", "\t", "\n", "\r"])
    end
  end

  @doc "An absolute http(s) URL on a named host other than `request_host`, else `nil`."
  def web_url(value, request_host) do
    with false <- blank?(value),
         false <- String.match?(value, ~r/[\s\x00-\x1F]/),
         %URI{scheme: scheme, host: host} when is_binary(scheme) <- URI.parse(value),
         true <- String.downcase(scheme) in ["http", "https"],
         true <- named_host?(host),
         true <- canonical_host(host) != canonical_host(request_host) do
      value
    else
      _ -> nil
    end
  end

  defp named_host?(host) when is_binary(host) do
    label = host |> String.trim_trailing(".") |> String.split(".") |> List.last()

    not blank?(host) and not String.contains?(host, "%") and String.contains?(host, ".") and
      label != nil and String.match?(label, ~r/[a-zA-Z]/) and
      not String.starts_with?(String.downcase(label), "0x")
  end

  defp named_host?(_), do: false

  defp canonical_host(host), do: host |> String.downcase() |> String.trim_trailing(".")

  ## Partials (as trees; the final scrub strips what doesn't survive)

  @doc "The attachable's partial, as tree nodes."
  def render({:user, user}, ctx, _attrs), do: ctx.mention.(user)
  def render({:opengraph, embed}, _ctx, _attrs), do: opengraph_partial(embed)

  def render({:content, nodes}, _ctx, _attrs),
    do: [{"figure", [{"class", "attachment attachment--content"}], nodes}]

  def render({:remote_image, image}, _ctx, attrs) do
    case image_src(image.url) do
      nil ->
        []

      src ->
        img_attrs =
          [{"width", image.width}, {"height", image.height}, {"src", src}]
          |> Enum.reject(&is_nil(elem(&1, 1)))

        [
          {"figure", [{"class", "attachment attachment--preview"}],
           [{"img", img_attrs, []} | caption(attrs)]}
        ]
    end
  end

  def render({:remote_video, _video}, _ctx, attrs),
    do: [
      {"figure", [{"class", "attachment attachment--preview attachment--video"}], caption(attrs)}
    ]

  def render(:missing, _ctx, _attrs), do: ["☒"]

  defp caption(attrs) do
    case attr(attrs, "caption") do
      nil -> []
      "" -> []
      caption -> [{"figcaption", [{"class", "attachment__caption"}], [caption]}]
    end
  end

  # image_tag: URLs and rooted paths pass; anything else would be an (unknown) asset, which raises.
  defp image_src(url) do
    cond do
      blank?(url) ->
        ""

      Regex.match?(~r{^[-a-z]+://|^(?:cid|data):|^//}im, url) or String.starts_with?(url, "/") ->
        url

      true ->
        nil
    end
  end

  defp opengraph_partial(embed) do
    title =
      case embed do
        %{href: href} when is_binary(href) ->
          [
            {"a", [{"rel", "noreferrer"}, {"target", "_blank"}, {"href", href}],
             [if(embed.filename, do: truncate(embed.filename, 280), else: href)]}
          ]

        %{filename: filename} when is_binary(filename) ->
          [truncate(filename, 280)]

        _ ->
          []
      end

    twitter =
      if String.starts_with?(embed.url || "", @twitter_avatar),
        do: "og-embed--twitter-avatar",
        else: ""

    image =
      if embed.url,
        do: [
          {"div", [{"class", "og-embed__image"}],
           [{"img", [{"src", embed.url}, {"class", "image center"}, {"alt", ""}], []}]}
        ],
        else: []

    [
      {"figure", [{"class", "attachment attachment--content attachment--og"}],
       [
         {"actiontext-opengraph-embed", [],
          [
            {"div", [{"class", "og-embed gap #{twitter}"}],
             [
               {"div", [{"class", "og-embed__content"}],
                [
                  {"div", [{"class", "og-embed__title"}], title},
                  {"div", [{"class", "og-embed__description"}],
                   [truncate(embed.description || "", 560)]}
                ]}
               | image
             ]}
          ]}
       ]}
    ]
  end

  # ActiveSupport's truncate with omission "…".
  defp truncate(text, length) do
    if String.length(text) > length, do: String.slice(text, 0, length - 1) <> "…", else: text
  end

  ## Plain text (Attachment#to_plain_text)

  @doc "The attachable's plain-text representation, as tree nodes to splice in."
  def plain_text({:user, user}, _attrs), do: HTML.parse("@" <> user.name)
  def plain_text({:opengraph, _}, _attrs), do: []
  def plain_text({:content, nodes}, _attrs), do: nodes

  def plain_text({:remote_image, _}, attrs),
    do: HTML.parse("[#{presence(attr(attrs, "caption")) || "Image"}]")

  def plain_text({:remote_video, video}, attrs),
    do: HTML.parse("[#{presence(attr(attrs, "caption")) || video.filename || "Video"}]")

  def plain_text(:missing, attrs), do: HTML.parse(presence(attr(attrs, "caption")) || "")

  defp presence(value), do: if(blank?(value), do: nil, else: value)
end
