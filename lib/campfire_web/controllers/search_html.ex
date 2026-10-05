defmodule CampfireWeb.SearchHTML do
  @moduledoc """
  `searches/index`. Results use `result/1`, a minimal port of `messages/_message`: the full
  message markup (actions, boosts) with the indexed plain text as the body.

  INTEGRATION NOTE: `result/1` duplicates the message partial owned by the messages work;
  replace it with that partial (and its preloads/cache) when merging. The body here is the
  FTS-indexed plain text, escaped, not the rich-text presentation.
  """
  use CampfireWeb, :html

  alias Campfire.Accounts.User

  embed_templates "search_html/*"

  def search_path(query), do: "/searches?" <> URI.encode_query(%{"q" => query})

  @doc "Recent searches and the clear button: in the nav, and again in the sidebar."
  attr :searches, :list, required: true

  def recent_searches(assigns) do
    ~H"""
    <a
      :for={search <- @searches}
      class="align-center gap room btn txt-nowrap"
      href={search_path(search.query)}
    >
      <span class="overflow-ellipsis">“{search.query}”</span>
    </a>

    <%= if @searches != [] do %>
      <form class="button_to" method="post" action="/searches/clear">
        <input
          type="hidden"
          name="_method"
          value="delete"
        /><button
          class="btn searches__btn"
          data-turbo-confirm="Are you sure you want to clear your recent searches?"
          type="submit"
        >
          <.image src="broom.svg" aria-hidden="true" />
          <span class="for-screen-reader">Clear recent searches</span>
        </button><.csrf_input />
      </form>
    <% end %>
    """
  end

  @boosts [
    {"👍", "Thumbs up"},
    {"👏", "Clapping"},
    {"👋", "Waving hand"},
    {"💪", "Muscle"},
    {"❤️", "Red heart"},
    {"😂", "Face with tears of joy"},
    {"🎉", "Party popper"},
    {"🔥", "Fire"}
  ]

  attr :message, :map, required: true
  attr :plain_text, :string, required: true
  attr :room_name, :string, required: true
  attr :base_url, :string, required: true, doc: "scheme + host of the request (copy-link URL)"

  def result(%{message: %{creator: nil}} = assigns) do
    ~H"""
    <div class="message message--formatted message--failed center">
      <div class="message__body">
        <div class="message__body-content txt-align-center">Failed to load message content</div>
      </div>
    </div>
    """
  end

  def result(assigns) do
    assigns = assign(assigns, :boost_options, @boosts)

    ~H"""
    <div
      id={"message_#{@message.client_message_id}"}
      class="message "
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
      <figure class="avatar message__avatar"><.avatar user={@message.creator} /></figure>
      <turbo-frame id={"edit_message_#{@message.client_message_id}"}>
        <div class="message__body">
          <div class="message__body-content">
            <div class="message__meta">
              <h3 class="message__heading">
                <span class="message__author" title={User.title(@message.creator)}>
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
              <div class="message__actions" data-controller="soft-keyboard">
                <details
                  class="position-relative"
                  data-controller="popup"
                  data-action="keydown.esc->popup#close toggle->popup#toggle click@document->popup#closeOnClickOutside"
                  data-popup-orientation-top-class="popup-orientation-top"
                >
                  <summary class="btn message__action-btn message__options-btn">
                    <.image
                      src="menu-dots-horizontal.svg"
                      size="20"
                      class="colorize--black"
                      aria-hidden="true"
                    />
                    <span class="for-screen-reader">Message options</span>
                  </summary>
                  <div class="message__actions-menu border shadow" data-popup-target="menu">
                    <div class="quick-boosts">
                      <form
                        :for={{emoji, title} <- @boost_options}
                        data-turbo-frame={"boosting_message_#{@message.client_message_id}"}
                        data-action="popup#close"
                        action={"/messages/#{@message.id}/boosts"}
                        accept-charset="UTF-8"
                        method="post"
                      >
                        <.csrf_input />
                        <input type="hidden" name="boost[content]" id="boost_content" value={emoji} />
                        <button
                          name="button"
                          type="submit"
                          title={title}
                          class="btn message__action-btn"
                          data-emoji={emoji}
                        >
                          <figure class="margin-none boost-character">{emoji}</figure>
                          <span class="for-screen-reader">{title}</span>
                        </button>
                      </form>
                      <a
                        class="btn message__action-btn message__boost-btn"
                        data-turbo-frame={"new_boost_message_#{@message.client_message_id}"}
                        data-action="soft-keyboard#open popup#close"
                        href={"/messages/#{@message.id}/boosts/new"}
                      >
                        <.image src="boost.svg" size="20" class="colorize--black" aria-hidden="true" />
                        <span class="for-screen-reader">New boost</span>
                      </a>
                    </div>
                    <div class="flex flex-wrap border-top margin-block-start-half pad-block-start-half message__actions-grid">
                      <button
                        class="btn message__action-btn center full-width"
                        data-action="reply#reply"
                        title="Reply"
                        aria-label="Reply"
                      >
                        <.image src="reply.svg" size="20" class="colorize--black" aria-hidden="true" />
                      </button>
                      <button
                        class="btn message__action-btn center full-width"
                        title="Copy link"
                        aria-label="Copy link"
                        data-controller="copy-to-clipboard"
                        data-action="copy-to-clipboard#copy"
                        data-copy-to-clipboard-success-class="btn--success"
                        data-copy-to-clipboard-content-value={"#{@base_url}/rooms/#{@message.room_id}/@#{@message.id}"}
                      >
                        <.image src="link.svg" size="20" class="colorize--black" aria-hidden="true" />
                      </button>
                      <a
                        class="btn message__action-btn center full-width message__edit-btn"
                        data-turbo-frame={"edit_message_#{@message.client_message_id}"}
                        title="Edit"
                        aria-label="Edit"
                        href={"/rooms/#{@message.room_id}/messages/#{@message.id}/edit"}
                      >
                        <.image src="pencil.svg" size="20" class="colorize--black" aria-hidden="true" />
                      </a>
                    </div>
                  </div>
                </details>
              </div>
            </div>
            <div
              id={"presentation_message_#{@message.client_message_id}"}
              dir="auto"
              data-reply-target="body"
              data-messages-target="body"
            >
              <div class="lexxy-content">
                {@plain_text}
              </div>
            </div>
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
                  <.boost :for={boost <- @message.boosts} boost={boost} />
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
          </div>
        </div>
      </turbo-frame>
    </div>
    """
  end

  attr :boost, :map, required: true

  defp boost(assigns) do
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
        class="txt-small"
        data-action="click->boost-delete#reveal keydown.enter->boost-delete#reveal:prevent"
        data-boost-delete-target="content"
      >{@boost.content}</span>
      <form
        class="button_to"
        method="post"
        action={"/messages/#{@boost.message_id}/boosts/#{@boost.id}"}
      >
        <input
          type="hidden"
          name="_method"
          value="delete"
        /><button
          data-action="boost-delete#perform"
          data-boost-delete-target="button"
          class="btn btn--negative flex-item-justify-end boost__delete"
          type="submit"
        >
          <.image src="minus.svg" size="20" aria-hidden="true" />
          <span class="for-screen-reader">Delete this boost</span>
        </button><.csrf_input />
      </form>
    </div>
    <span id="delete_boost_accessible_label" class="for-screen-reader">Press enter to delete this boost</span>
    """
  end
end
