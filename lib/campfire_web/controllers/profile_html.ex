defmodule CampfireWeb.ProfileHTML do
  @moduledoc "`users/profiles/show`: avatar, name/email/password/bio, room notifications."
  use CampfireWeb, :html

  import CampfireWeb.UserComponents
  import CampfireWeb.Rooms.InvolvementHTML, only: [involvement_button: 1]

  alias Campfire.Rooms
  alias Campfire.Rooms.Room

  embed_templates "profile_html/*"

  attr :membership, :any, required: true
  attr :name, :string, required: true

  def membership(assigns) do
    ~H"""
    <li class="flex align-center gap margin-none min-width membership-item">
      <a
        class="overflow-ellipsis fill-shade txt-primary txt-undecorated"
        href={"/rooms/#{@membership.room_id}"}
      >
        <strong>{@name}</strong>
      </a>

      <hr class="separator" aria-hidden="true" />

      <span class="txt-small">
        <turbo-frame id={"involvement_#{Room.param_key(@membership.room)}_#{@membership.room_id}"}>
          <.involvement_button
            room={@membership.room}
            involvement={@membership.involvement || Rooms.default_involvement(@membership.room.type)}
          />
        </turbo-frame>
      </span>
    </li>
    """
  end

  attr :class, :string, default: nil
  attr :multipart, :boolean, default: false
  slot :inner_block, required: true

  def profile_form(assigns) do
    ~H"""
    <form
      class={@class}
      data-controller="form"
      enctype={@multipart && "multipart/form-data"}
      action="/users/me/profile"
      accept-charset="UTF-8"
      method="post"
    >
      <input type="hidden" name="_method" value="patch" /><.csrf_input />
      {render_slot(@inner_block)}
    </form>
    """
  end

  attr :id, :string, default: "file"

  def avatar_input(assigns) do
    ~H"""
    <input
      id={@id}
      class="input"
      accept="image/*"
      data-upload-preview-target="input"
      data-action="upload-preview#previewImage change->form#submit"
      type="file"
      name="user[avatar]"
    />
    """
  end
end
