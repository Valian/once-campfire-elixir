defmodule CampfireWeb.SearchHTML do
  @moduledoc """
  `searches/index`. Results are message partials (`CampfireWeb.MessageRenderer`).
  """
  use CampfireWeb, :html

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
end
