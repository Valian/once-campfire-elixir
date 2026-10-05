defmodule CampfireWeb.AutocompletableUserHTML do
  @moduledoc """
  `autocompletable/users/_prompt_item` and `users/_mention` (the editor-side mention span,
  with the attachable sgid). NOTE: the rich-text work renders mentions too; dedupe at merge.
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
        <.mention user={@user} sgid={@sgid} />
      </template>
    </lexxy-prompt-item>
    """
  end

  attr :user, :any, required: true
  attr :sgid, :string, required: true

  def mention(assigns) do
    ~H"""
    <span class="mention" sgid={@sgid}><.avatar user={@user} /> {@user.name}</span>
    """
  end
end
