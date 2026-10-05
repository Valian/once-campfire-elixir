defmodule Campfire.RichText.Sanitizer do
  @moduledoc """
  The allowlists of the presentation pipeline (SPEC §9.2) and one scrubber that applies them,
  following `Rails::HTML5::SafeListSanitizer`/Loofah: disallowed HTML elements are unwrapped
  (children kept), foreign ones (SVG, MathML) dropped with their contents, comments dropped,
  attributes outside the list dropped, URL attributes with unsafe schemes dropped.

  `drop_disallowed/2` is `ContentFilters::SanitizeTags`: disallowed elements go with their contents.
  """

  @default_tags ~w(a abbr acronym address b big blockquote br cite code dd del dfn div dl dt em
                   h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark ol p pre samp small span strong sub
                   sup time tt ul var)
  # `name` is in Rails' defaults; it lets a message clobber DOM globals, and nothing writes it.
  @default_attributes ~w(abbr alt cite class datetime height href lang src title width xml:lang)
  @editor_tags ~w(s u mark table thead tbody tfoot tr th td)
  @attachment_attributes ~w(sgid content-type url href filename filesize width height previewable
                            presentation caption content)

  @sanitize_tags_tags (~w(a abbr acronym address b big blockquote br cite code dd del dfn div dl dt
                          em h1 h2 h3 h4 h5 h6 hr i ins kbd li ol p pre samp small span strong sub
                          sup time tt ul var) ++
                         @editor_tags ++ ~w(action-text-attachment figure figcaption))
                      |> MapSet.new()

  @action_text_attributes (@default_attributes ++
                             @attachment_attributes ++
                             ~w(controls poster data-language style value start))
                          |> MapSet.new()

  @lists %{
    # ContentFilters::SanitizeAttributes: SanitizeTags' tags, Action Text's attributes + class
    content_filter: {@sanitize_tags_tags, @action_text_attributes},
    # Action Text's own sanitizer (attachment `content` attributes, nested content)
    action_text:
      {MapSet.new(
         @default_tags ++
           @editor_tags ++
           ~w(action-text-attachment figure figcaption video audio source embed)
       ), @action_text_attributes},
    # MessagesHelper::AUTO_LINK_ALLOWED_TAGS / _ATTRIBUTES: bounds the final output
    auto_link:
      {MapSet.new(@default_tags ++ @editor_tags),
       MapSet.new(@default_attributes ++ ~w(data-language))}
  }

  @foreign ~w(svg math)
  @uri_attributes ~w(action cite href longdesc poster preload src xlink:href xml:base)

  @doc "`ContentFilters::SanitizeTags`: removes elements outside its list, with their contents."
  def drop_disallowed(tree) do
    Enum.flat_map(tree, fn
      {tag, attrs, children} when is_binary(tag) ->
        if MapSet.member?(@sanitize_tags_tags, tag),
          do: [{tag, attrs, drop_disallowed(children)}],
          else: []

      other ->
        [other]
    end)
  end

  @doc "Scrubs `tree` with one of the lists: `:content_filter`, `:action_text`, `:auto_link`."
  def scrub(tree, list) when is_atom(list) do
    {tags, attributes} = Map.fetch!(@lists, list)
    scrub(tree, tags, attributes)
  end

  defp scrub(tree, tags, attributes) do
    Enum.flat_map(tree, fn
      text when is_binary(text) ->
        [text]

      {:comment, _} ->
        []

      {tag, attrs, children} ->
        cond do
          MapSet.member?(tags, tag) ->
            [{tag, scrub_attributes(attrs, attributes), scrub(children, tags, attributes)}]

          tag in @foreign ->
            []

          true ->
            scrub(children, tags, attributes)
        end
    end)
  end

  defp scrub_attributes(attrs, allowed) do
    for {name, value} <- attrs,
        MapSet.member?(allowed, name),
        name not in @uri_attributes or allowed_uri?(value),
        not (name == "src" and String.trim(value) == "") do
      {name, escape_url_attribute(name, value)}
    end
  end

  # Loofah's force_correct_attribute_escaping: spaces and quotes in URLs are percent-escaped.
  defp escape_url_attribute(name, value) when name in ~w(href action src) do
    if String.contains?(value, [" ", "\""]) or
         String.match?(value, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/) do
      value
      |> String.replace(" ", "%20")
      |> String.replace("\"", "%22")
      |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    else
      value
    end
  end

  defp escape_url_attribute(_name, value), do: value

  @protocols ~w(afs aim callto data ed2k fax ftp gopher http https irc line mailto modem news nntp
                rsync rtsp sftp sms ssh tag tel telnet urn webcal xmpp)
  @data_mediatypes ~w(image/gif image/jpeg image/png text/css text/plain)
  # Loofah's CONTROL_CHARACTERS: /[`\u0000- \u007f\u0080-ā]/
  @controls ~r/[`\x{0000}-\x{0020}\x{007F}\x{0080}-\x{0101}]/u

  @doc "`Loofah::HTML5::Scrub.allowed_uri?`"
  def allowed_uri?(uri) do
    s =
      uri
      |> String.replace(@controls, "")
      |> unescape_html()
      |> String.replace(@controls, "")
      |> String.replace(["&Tab;", "&NewLine;"], "")
      |> String.replace("&colon;", ":")
      |> String.downcase()

    case Regex.run(~r/\A([a-z][a-z0-9+\-.]*)(:|&#0*58|&#x0*3a|%3a|&#37;3a)/i, s) do
      nil -> true
      [_, "data", _] -> data_mediatype(s) in @data_mediatypes
      [_, protocol, _] -> protocol in @protocols
    end
  end

  defp data_mediatype(s) do
    rest = String.replace_prefix(s, "data:", "")

    case String.split(rest, ",", parts: 2) do
      [metadata, _] ->
        mediatype =
          metadata
          |> String.replace_suffix(";base64", "")
          |> String.split(";")
          |> hd()
          |> String.trim(" ")

        if Regex.match?(~r/\A[a-z0-9!#$%&'*+\-.^_`|~]+\/[a-z0-9!#$%&'*+\-.^_`|~]+\z/, mediatype),
          do: mediatype,
          else: "text/plain"

      _ ->
        nil
    end
  end

  # CGI.unescapeHTML plus numeric character references, as Loofah decodes before checking.
  defp unescape_html(s) do
    if String.contains?(s, "&") do
      Regex.replace(~r/&(?:(amp|quot|apos|lt|gt)|#(\d+)|#x([0-9a-f]+));/i, s, fn
        _, "amp", _, _ -> "&"
        _, "quot", _, _ -> "\""
        _, "apos", _, _ -> "'"
        _, "lt", _, _ -> "<"
        _, "gt", _, _ -> ">"
        whole, "", dec, "" -> codepoint(String.to_integer(dec), whole)
        whole, "", "", hex -> codepoint(String.to_integer(hex, 16), whole)
        whole, _, _, _ -> whole
      end)
    else
      s
    end
  end

  defp codepoint(cp, _whole) when cp in 0..0x10FFFF and cp not in 0xD800..0xDFFF, do: <<cp::utf8>>
  defp codepoint(_, whole), do: whole
end
