defmodule CampfireWeb.Rooms.RoomFormHTML do
  @moduledoc """
  Pieces shared by the open/closed/direct room pages: `rooms/layouts/{_new,_edit,_form}`,
  the user filter menu and rows, the back link and the delete button.
  """
  use CampfireWeb, :html

  alias Campfire.Accounts.User
  alias Campfire.Rooms.Room

  @doc "Rails `link_back_to_last_room_visited`."
  attr :room, :any, required: true, doc: "the last room visited, or nil"

  def back_link(assigns) do
    ~H"""
    <div class="flex-item-justify-start">
      <a class="btn" href={if @room, do: "/rooms/#{@room.id}", else: "/"}><.image
        src="arrow-left.svg"
        size="20"
        aria-hidden="true"
      /><span class="for-screen-reader">Go Back</span></a>
    </div>
    """
  end

  @doc "`rooms/layouts/_new` + `_edit`: the page around a room form."
  attr :flash, :map, required: true
  attr :current_user, User, required: true
  attr :turbo_frame, :any, required: true
  attr :last_room, :any, required: true
  attr :room, Room, default: nil, doc: "nil for a new room"
  attr :can_administer, :boolean, required: true
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      turbo_frame={@turbo_frame}
      title={if @room, do: "Edit settings for #{@room.name}", else: "New chat room"}
    >
      <:nav><.back_link room={@last_room} /></:nav>

      <section
        class="panel txt-align-center"
        style={"view-transition-name: #{if @room, do: "edit-room-#{@room.id}", else: "new-room"}"}
      >
        {render_slot(@inner_block)}
      </section>

      <%= if @room && @can_administer do %>
        <section class="panel txt-align-center">
          <.delete_button action={"/rooms/#{@room.id}"} room_name={@room.name} />
        </section>
      <% end %>
    </Layouts.app>
    """
  end

  @doc "Rails `button_to_delete_room`."
  attr :action, :string, required: true
  attr :room_name, :string, required: true

  def delete_button(assigns) do
    ~H"""
    <form class="button_to" method="post" action={@action}>
      <input
        type="hidden"
        name="_method"
        value="delete"
      /><button
        class="btn btn--negative max-width"
        aria-label={"Delete #{@room_name}"}
        data-turbo-confirm="Are you sure you want to delete this room and all messages in it? This can’t be undone."
        type="submit"
      ><.image src="trash.svg" size="20" aria-hidden="true" /><span class="overflow-ellipsis">{@room_name}</span></button><.csrf_input />
    </form>
    """
  end

  @doc "`rooms/layouts/_form`: name field (or heading) and the access list."
  attr :action, :string, required: true
  attr :method, :string, default: nil
  attr :name, :string, required: true
  attr :can_administer, :boolean, required: true
  slot :inner_block, required: true

  def room_form(assigns) do
    ~H"""
    <form action={@action} accept-charset="UTF-8" method="post">
      <input
        :if={@method}
        type="hidden"
        name="_method"
        value={@method}
      /><.csrf_input />
      <div class="flex align-center gap">
        <%= if @can_administer do %>
          <.translation_button key={:room_name} />

          <label class="flex-item-grow txt-large">
            <input
              name="room[name]"
              id="room_name"
              class="input full-width"
              required="required"
              autofocus="autofocus"
              placeholder="Name the room"
              data-turbo-permanent="true"
              data-action="keydown.enter->form#submit:prevent"
              type="text"
              value={@name}
            />
            <span class="for-screen-reader">Name this room</span>
          </label>
        <% else %>
          <h1 class="flex-item-grow txt-x-large">
            {@name}
          </h1>
        <% end %>
      </div>

      <hr class="margin-block borderless" />

      <section class="room-access margin-block pad-inline fill-shade border-radius">
        <menu
          class="flex flex-column gap margin-none pad overflow-y constrain-height"
          data-controller="filter"
          data-filter-active-class="filter--active"
          data-filter-selected-class="selected"
        >
          {render_slot(@inner_block)}
        </menu>
      </section>

      <button
        :if={@can_administer}
        name="button"
        type="submit"
        class="btn btn--reversed txt-large center"
      ><.image src="check.svg" size="20" aria-hidden="true" /><span class="for-screen-reader">Save</span></button>
    </form>
    """
  end

  @doc "The \"Everyone\" row; the switch converts the room between open and closed."
  attr :type_change_path, :string, default: nil, doc: "nil hides the switch"
  attr :open, :boolean, required: true

  def everyone(assigns) do
    ~H"""
    <li class="flex align-center gap margin-none">
      <figure
        class="avatar flex-item-no-shrink"
        style="--avatar-border-radius: 0; --avatar-size: 4ch;"
      >
        <.image
          src="everyone.svg"
          aria-hidden="true"
          class="colorize--black"
          style="background-color: transparent"
        />
        <span class="for-screen-reader">Everyone</span>
      </figure>

      <div class="min-width">
        <div class="overflow-ellipsis fill-shade"><strong>Everyone</strong></div>
      </div>

      <hr class="separator" aria-hidden="true" />

      <a
        :if={@type_change_path}
        class="btn--faux flex-inline"
        tabindex="-1"
        data-turbo-action="replace"
        href={@type_change_path}
      >
        <label for="room_type" class="switch">
          <input type="checkbox" id="room_type" class="switch__input" checked={@open} />
          <span class="switch__btn round"></span>
          <span class="for-screen-reader">
            {if @open,
              do: "Give only some access to this room",
              else: "Give everyone access to this room"}
          </span>
        </label>
      </a>
    </li>

    <hr class="separator full-width" style="--border-style: solid" />
    """
  end

  @doc "Rails `user_filter_search_tag`, shown when there are more than 20 users."
  def filter_search(assigns) do
    ~H"""
    <input
      type="search"
      id="search"
      autocorrect="off"
      autocomplete="off"
      data-1p-ignore="true"
      class="input input--transparent full-width"
      placeholder="Filter…"
      data-action="input->filter#filter"
    />
    """
  end

  @doc "A user in the access list; the inner block is the row's control (check, switch, …)."
  attr :user, User, required: true
  slot :inner_block

  def user_row(assigns) do
    ~H"""
    <li class="flex align-center gap margin-none" data-value={String.downcase(@user.name)}>
      <figure class="avatar flex-item-no-shrink" style="--avatar-size: 4ch;">
        <.avatar user={@user} img={%{"aria-hidden" => "true", "loading" => "lazy"}} />
      </figure>

      <div class="min-width">
        <div class="overflow-ellipsis fill-shade"><strong>{@user.name}</strong></div>
      </div>

      <hr class="separator" aria-hidden="true" />

      {render_slot(@inner_block)}
    </li>
    """
  end

  def check(assigns) do
    ~H"""
    <.image src="check.svg" size="20" class="colorize--black flex-item-no-shrink" aria-hidden="true" />
    """
  end
end
