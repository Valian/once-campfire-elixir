defmodule CampfireWeb.MessageComponents do
  @moduledoc """
  The message partial and its parts (ports of `messages/_message`, `_actions`, `_presentation`,
  `boosts/_boosts`, `boosts/_boost`, `Messages::AttachmentPresentation`). Markup is the
  contract (SPEC §8): attribute order follows Rails.

  The partial doesn't depend on the viewer except through `csrf` (the forms' token) and
  `base_url` (the copy-link URL); `CampfireWeb.MessageRenderer` renders it with placeholders
  for both and caches the result.
  """
  use CampfireWeb, :html

  alias Campfire.Messages.Sound
  alias Campfire.Storage
  alias CampfireWeb.Assets

  @reactions [
    {"👍", "Thumbs up"},
    {"👏", "Clapping"},
    {"👋", "Waving hand"},
    {"💪", "Muscle"},
    {"❤️", "Red heart"},
    {"😂", "Face with tears of joy"},
    {"🎉", "Party popper"},
    {"🔥", "Fire"}
  ]

  @doc "Renders a function component outside a template, to iodata."
  def to_iodata(component, assigns) when is_function(component, 1),
    do: assigns |> Map.put(:__changed__, nil) |> component.() |> Phoenix.HTML.Safe.to_iodata()

  @doc """
  One message. Assigns: `message` (with creator, boosts and attachment preloaded), `room_name`,
  `presentation` (the body's iodata), `emoji` (all-emoji body), `csrf`, `base_url`.
  """
  attr :message, :map, required: true
  attr :room_name, :string, required: true
  attr :presentation, :any, required: true
  attr :emoji, :boolean, default: false
  attr :csrf, :string, required: true
  attr :base_url, :string, required: true

  def message(assigns) do
    ~H"""
    <div
      id={"message_#{@message.client_message_id}"}
      class={"message #{if @emoji, do: "message--emoji"}"}
      data-controller="reply"
      data-user-id={@message.creator_id}
      data-message-id={@message.id}
      data-message-timestamp={epoch_ms(@message.created_at)}
      data-message-updated-at={epoch_ms(@message.updated_at)}
      data-sort-value={epoch_ms(@message.created_at)}
      data-messages-target="message"
      data-search-results-target="message"
      data-refresh-room-target="message"
      data-reply-composer-outlet="#composer"
    >
      <h2 class="message__day-separator">
        <.local_datetime at={@message.created_at} style="date" />
      </h2>

      <figure class="avatar message__avatar">
        <.avatar user={@message.creator} />
      </figure>

      <turbo-frame id={"edit_message_#{@message.client_message_id}"}>
        <div class="message__body">
          <div class="message__body-content">
            <div class="message__meta">
              <h3 class="message__heading">
                <span class="message__author" title={Campfire.Accounts.User.title(@message.creator)}>
                  <strong data-reply-target="author">{@message.creator.name}</strong>
                </span>
                <a
                  target="_top"
                  class="message__permalink"
                  href={"/rooms/#{@message.room_id}/@#{@message.id}"}
                ><.local_datetime at={@message.created_at} class="message__timestamp" /></a>
                <span class="message__room">
                  <a
                    target="_top"
                    data-reply-target="link"
                    href={"/rooms/#{@message.room_id}/@#{@message.id}"}
                  >{@room_name}</a>
                </span>
              </h3>
              <.actions message={@message} csrf={@csrf} base_url={@base_url} />
            </div>
            <.presentation message={@message} content={@presentation} />
            <.boosts message={@message} csrf={@csrf} />
          </div>
        </div>
      </turbo-frame>
    </div>
    """
  end

  @doc "`messages/_unrenderable`: what shows when a message can't be rendered."
  def unrenderable(assigns) do
    ~H"""
    <div class="message message--formatted message--failed center">
      <div class="message__body">
        <div class="message__body-content txt-align-center">
          Failed to load message content
        </div>
      </div>
    </div>
    """
  end

  @doc "`messages/_presentation`: the body's container (also the update broadcast's payload)."
  attr :message, :map, required: true
  attr :content, :any, required: true, doc: "`{:safe, iodata}`"

  def presentation(assigns) do
    ~H"""
    <div
      id={"presentation_message_#{@message.client_message_id}"}
      dir="auto"
      data-reply-target="body"
      data-messages-target="body"
    >
      {@content}
    </div>
    """
  end

  attr :message, :map, required: true
  attr :csrf, :string, required: true
  attr :base_url, :string, required: true

  def actions(assigns) do
    assigns =
      assign(assigns, reactions: @reactions, blob: attachment_blob(assigns.message))

    ~H"""
    <div class="message__actions" data-controller="soft-keyboard">
      <details
        class="position-relative"
        data-controller="popup"
        data-action="keydown.esc->popup#close toggle->popup#toggle click@document->popup#closeOnClickOutside"
        data-popup-orientation-top-class="popup-orientation-top"
      >
        <summary class="btn message__action-btn message__options-btn">
          <.image src="menu-dots-horizontal.svg" size="20" class="colorize--black" aria-hidden="true" />
          <span class="for-screen-reader">Message options</span>
        </summary>

        <div class="message__actions-menu border shadow" data-popup-target="menu">
          <div class="quick-boosts">
            <%= for {character, title} <- @reactions do %>
              <form
                data-turbo-frame={"boosting_message_#{@message.client_message_id}"}
                data-action="popup#close"
                action={"/messages/#{@message.id}/boosts"}
                accept-charset="UTF-8"
                method="post"
              >
                <input type="hidden" name="authenticity_token" value={@csrf} />
                <input type="hidden" name="boost[content]" id="boost_content" value={character} />
                <button
                  name="button"
                  type="submit"
                  title={title}
                  class="btn message__action-btn"
                  data-emoji={character}
                >
                  <figure class="margin-none boost-character">{character}</figure>
                  <span class="for-screen-reader">{title}</span>
                </button>
              </form>
            <% end %>

            <a
              class="btn message__action-btn message__boost-btn"
              data-turbo-frame={"new_boost_message_#{@message.client_message_id}"}
              data-action="soft-keyboard#open popup#close"
              href={"/messages/#{@message.id}/boosts/new"}
            >
              <.image src="boost.svg" class="colorize--black" size="20" aria-hidden="true" />
              <span class="for-screen-reader">New boost</span>
            </a>
          </div>

          <div class="flex flex-wrap border-top margin-block-start-half pad-block-start-half message__actions-grid">
            <%= if @blob do %>
              <a
                class="btn message__action-btn center full-width hide-in-ios-pwa"
                title="Download"
                aria-label="Download"
                href={Storage.blob_path(@blob, disposition: "attachment")}
              >
                <.image src="download.svg" class="colorize--black" size="20" aria-hidden="true" />
              </a>

              <button
                class="btn message__action-btn center full-width"
                data-controller="web-share"
                data-action="web-share#share"
                data-web-share-files-value={Storage.blob_path(@blob)}
                data-web-share-title-value={@blob.filename}
                title="Share"
                aria-label="Share"
              >
                <.image src="share.svg" class="colorize--black" size="20" aria-hidden="true" />
              </button>
            <% else %>
              <button
                class="btn message__action-btn center full-width"
                data-action="reply#reply"
                title="Reply"
                aria-label="Reply"
              >
                <.image src="reply.svg" class="colorize--black" size="20" aria-hidden="true" />
              </button>
            <% end %>

            <button
              class="btn message__action-btn center full-width"
              title="Copy link"
              aria-label="Copy link"
              data-controller="copy-to-clipboard"
              data-action="copy-to-clipboard#copy"
              data-copy-to-clipboard-success-class="btn--success"
              data-copy-to-clipboard-content-value={"#{@base_url}/rooms/#{@message.room_id}/@#{@message.id}"}
            >
              <.image src="link.svg" class="colorize--black" size="20" aria-hidden="true" />
            </button>

            <a
              class="btn message__action-btn center full-width message__edit-btn"
              data-turbo-frame={"edit_message_#{@message.client_message_id}"}
              title="Edit"
              aria-label="Edit"
              href={"/rooms/#{@message.room_id}/messages/#{@message.id}/edit"}
            >
              <.image src="pencil.svg" class="colorize--black" size="20" aria-hidden="true" />
            </a>
          </div>
        </div>
      </details>
    </div>
    """
  end

  @doc "`messages/boosts/_boosts`: the boosts frame under a message."
  attr :message, :map, required: true
  attr :csrf, :string, required: true

  def boosts(assigns) do
    ~H"""
    <turbo-frame id={"boosting_message_#{@message.client_message_id}"}>
      <div
        class="boosts flex flex-wrap align-center gap full-width"
        style="--column-gap: 0.4ch; --row-gap: 0"
        data-controller="turbo-streaming"
        data-action="turbo:submit-start->turbo-streaming#unsubscribe"
      >
        <div
          class="flex-inline flex-wrap gap"
          id={"boosts_message_#{@message.client_message_id}"}
          data-turbo-streaming-target="container"
        >
          <%= for boost <- @message.boosts do %>
            <.boost boost={boost} csrf={@csrf} />
          <% end %>
        </div>

        <turbo-frame id={"new_boost_message_#{@message.client_message_id}"}>
          <div class="flex-inline message__boost-inline" data-controller="soft-keyboard">
            <a
              class="boost__action txt-small btn"
              action="soft-keyboard#open"
              href={"/messages/#{@message.id}/boosts/new"}
            >
              <.image src="boost.svg" size="20" aria-hidden="true" />
              <span class="for-screen-reader">Add a boost</span>
            </a>
          </div>
        </turbo-frame>
      </div>
    </turbo-frame>
    """
  end

  @doc "`messages/boosts/_boost` (also the boost-create broadcast payload)."
  attr :boost, :map, required: true
  attr :csrf, :string, required: true

  def boost(assigns) do
    ~H"""
    <div
      id={"boost_#{@boost.id}"}
      class="boost boost-item flex-inline postion--relative max-width align-center fill-white gap"
      data-controller="boost-delete"
      data-boost-delete-perform-class="boost--deleting"
      data-boost-delete-reveal-class="expanded"
      data-boost-delete-booster-id-value={@boost.booster_id}
    >
      <figure class="avatar boost__avatar flex-item-no-shrink">
        <.avatar
          user={@boost.booster}
          img={%{"aria-label" => "#{@boost.booster.name} boosted #{@boost.content}"}}
        />
      </figure>

      <span
        role="button"
        class={["txt-small", Campfire.RichText.all_emoji?(@boost.content) && "txt-medium"]}
        data-action="click->boost-delete#reveal keydown.enter->boost-delete#reveal:prevent"
        data-boost-delete-target="content"
      >{@boost.content}</span>

      <form
        class="button_to"
        method="post"
        action={"/messages/#{@boost.message_id}/boosts/#{@boost.id}"}
      >
        <input type="hidden" name="_method" value="delete" /><button
          data-action="boost-delete#perform"
          data-boost-delete-target="button"
          class="btn btn--negative flex-item-justify-end boost__delete"
          type="submit"
        ><.image src="minus.svg" size="20" aria-hidden="true" />
        <span class="for-screen-reader">Delete this boost</span></button><input
          type="hidden"
          name="authenticity_token"
          value={@csrf}
        />
      </form>
    </div>
    <span id="delete_boost_accessible_label" class="for-screen-reader">
      Press enter to delete this boost
    </span>
    """
  end

  ## Presentations

  @doc "A `/play` sound message."
  attr :name, :string, required: true
  attr :sound, :any, required: true

  def sound(assigns) do
    ~H"""
    <div
      class="sound"
      data-controller="sound"
      data-action="messages:play->sound#play"
      data-sound-url-value={Assets.path(@name <> ".mp3")}
    >
      <button class="btn btn--plain" data-action="sound#play">🔊</button>
      <%= case @sound do %>
        <% {:image, asset, w, h} -> %>
          <img
            width={w}
            height={h}
            class="align--middle"
            src={Assets.path(asset)}
          />
        <% {:text, text} -> %>
          {text}
      <% end %>
    </div>
    """
  end

  @thumb_w 1200
  @thumb_h 800

  @doc "`Messages::AttachmentPresentation#render`"
  attr :blob, :map, required: true

  def attachment(assigns) do
    blob = assigns.blob

    kind =
      cond do
        Storage.video?(blob) -> :video
        Storage.variable?(blob) -> :image
        true -> :file
      end

    {w, h} = preview_dimensions(blob.metadata)
    assigns = assign(assigns, kind: kind, w: w, h: h)

    ~H"""
    <%= case @kind do %>
      <% :video -> %>
        <.media_box w={@w} h={@h}>
          <video
            src={Storage.blob_path(@blob)}
            poster={Storage.representation_path(@blob, Storage.poster())}
            controls="controls"
            preload="none"
            width="100%"
            height="100%"
            class="message__attachment"
          ></video>
        </.media_box>
      <% :image -> %>
        <.media_box w={@w} h={@h}>
          <a
            class="flex"
            data-lightbox-target="image"
            data-action="lightbox#open"
            data-lightbox-url-value={Storage.blob_path(@blob, disposition: "attachment")}
            href={Storage.blob_path(@blob)}
          ><img
            width={number(@w)}
            height={number(@h)}
            class="message__attachment"
            loading="lazy"
            src={Storage.representation_path(@blob, Storage.thumb(@blob))}
          /></a>
        </.media_box>
      <% :file -> %>
        <div class="flex-inline align-center gap-half">
          <.image src="common-file-text.svg" size="22" class="colorize--black" aria-hidden="true" /><span>{@blob.filename}</span><a
            class="btn message__action-btn hide-in-ios-pwa"
            style="--width: auto;"
            href={Storage.blob_path(@blob, disposition: "attachment")}
          ><.image src="download.svg" aria-hidden="true" size="20" /><span class="for-screen-reader">Download {@blob.filename}</span></a><button
            class="btn message__action-btn"
            style="--width: auto;"
            data-controller="web-share"
            data-action="web-share#share"
            data-web-share-files-value={Storage.blob_path(@blob, disposition: "attachment")}
          ><.image src="share.svg" aria-hidden="true" size="20" /><span class="for-screen-reader">Share {@blob.filename}</span></button>
        </div>
    <% end %>
    """
  end

  attr :w, :any, required: true
  attr :h, :any, required: true
  slot :inner_block, required: true

  defp media_box(%{w: w, h: h} = assigns) when is_number(w) and is_number(h) do
    assigns =
      assign(assigns, :style, "width: #{number(half(w))}px; aspect-ratio: #{number(w / h)};")

    ~H"""
    <div class="max-inline-size center flex overflow-clip" style={@style}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp media_box(assigns) do
    ~H"""
    <div class="max-inline-size center overflow-clip">{render_slot(@inner_block)}</div>
    """
  end

  # Ruby: integers divide as integers, floats print with a fractional part.
  defp half(w) when is_integer(w), do: div(w, 2)
  defp half(w), do: w / 2

  defp number(nil), do: nil
  defp number(n) when is_integer(n), do: Integer.to_string(n)
  defp number(n) when is_float(n), do: ruby_float(n)

  @doc false
  # Ruby's Float#to_s: the shortest round-tripping digits, in positional notation between 1e-4
  # and 1e16 (Erlang's shortest form switches to an exponent much sooner: 1200.0 is "1.2e3").
  def ruby_float(f) when is_float(f) do
    short = :erlang.float_to_binary(f, [:short])

    with [mantissa, exp] <- String.split(short, "e"),
         true <- abs(f) >= 1.0e-4 and abs(f) < 1.0e16 do
      {sign, mantissa} =
        if String.starts_with?(mantissa, "-"),
          do: {"-", String.slice(mantissa, 1..-1//1)},
          else: {"", mantissa}

      [int, frac] =
        String.split(mantissa <> if(String.contains?(mantissa, "."), do: "", else: ".0"), ".")

      digits = String.trim_trailing(int <> frac, "0") |> then(&if(&1 == "", do: "0", else: &1))
      point = String.length(int) + String.to_integer(exp)

      positional =
        cond do
          point >= String.length(digits) ->
            digits <> String.duplicate("0", point - String.length(digits)) <> ".0"

          point > 0 ->
            String.slice(digits, 0, point) <> "." <> String.slice(digits, point..-1//1)

          true ->
            "0." <> String.duplicate("0", -point) <> digits
        end

      sign <> positional
    else
      _ -> short
    end
  end

  defp preview_dimensions(%{"width" => w, "height" => h}) when is_number(w) and is_number(h) do
    if w <= @thumb_w and h <= @thumb_h do
      {w, h}
    else
      scale = min(@thumb_w / w, @thumb_h / h)
      {w * scale, h * scale}
    end
  end

  defp preview_dimensions(_), do: {nil, nil}

  defp attachment_blob(%{attachment: %{blob: %{} = blob}}), do: blob
  defp attachment_blob(_), do: nil

  @doc "The sound a message plays (`/play name` with a known name), as `{name, sound}`, or `nil`."
  defdelegate sound_for(text), to: Sound, as: :for_text
end
