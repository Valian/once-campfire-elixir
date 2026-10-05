defmodule CampfireWeb.AutocompletableUserHTML do
  @moduledoc """
  `autocompletable/users/_prompt_item`; its editor template is `users/_mention`
  (`CampfireWeb.Mention`).
  """
  use CampfireWeb, :html

  alias Campfire.Signing

  def render_items(users) do
    %{users: users}
    |> items()
    |> Phoenix.HTML.Safe.to_iodata()
  end

  defp items(assigns) do
    ~H"""
    <.prompt_item :for={user <- @users} user={user} />
    """
  end

  attr :user, :any, required: true

  def prompt_item(assigns) do
    assigns = assign(assigns, :sgid, Signing.sgid("User", assigns.user.id))

    ~H"""
    <lexxy-prompt-item search={@user.name} sgid={@sgid}>
      <template type="menu">
        <span class="autocomplete__item flex align-center gap unpad">
          <.avatar user={@user} />
          <span class="autocompletable__name">{@user.name}</span>
        </span>
      </template>
      <template type="editor">
        {CampfireWeb.Mention.editor_html(@user)}
      </template>
    </lexxy-prompt-item>
    """
  end
end
