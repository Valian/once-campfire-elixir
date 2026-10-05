defmodule CampfireWeb.Rooms.ClosedHTML do
  @moduledoc "`rooms/closeds/{new,edit,_form,_user}`."
  use CampfireWeb, :html

  import CampfireWeb.Rooms.RoomFormHTML

  # Rendered by the controller: `assigns` is a plain map here.
  def form(assigns) do
    assigns =
      Map.put(assigns, :member_opts, %{
        can_administer: assigns.can_administer,
        new_room: assigns.room == nil,
        current_user_id: assigns.current_user.id
      })

    ~H"""
    <.page
      flash={@flash}
      current_user={@current_user}
      turbo_frame={@turbo_frame}
      last_room={@last_room}
      room={@room}
      can_administer={@can_administer}
    >
      <.room_form
        action={if @room, do: "/rooms/closeds/#{@room.id}", else: "/rooms/closeds"}
        method={@room && "patch"}
        name={@name}
        can_administer={@can_administer}
      >
        <.everyone
          :if={@can_administer}
          open={false}
          type_change_path={if @room, do: "/rooms/opens/#{@room.id}/edit", else: "/rooms/opens/new"}
        />

        <.filter_search :if={length(@selected_users) + length(@unselected_users) > 20} />

        <div data-filter-target="list" contents>
          <.member
            :for={user <- @selected_users}
            user={user}
            selected={true}
            {@member_opts}
          />

          <hr
            :if={@selected_users != [] and @unselected_users != []}
            class="separator full-width"
            style="--border-style: solid"
          />

          <.member
            :for={user <- @unselected_users}
            user={user}
            selected={false}
            {@member_opts}
          />
        </div>
      </.room_form>
    </.page>
    """
  end

  attr :user, :any, required: true
  attr :selected, :boolean, required: true
  attr :can_administer, :boolean, required: true
  attr :new_room, :boolean, required: true
  attr :current_user_id, :integer, required: true

  defp member(assigns) do
    ~H"""
    <.user_row user={@user}>
      <%= cond do %>
        <% not @can_administer -> %>
        <% @new_room and @user.id == @current_user_id -> %>
          <input type="hidden" name="user_ids[]" value={@user.id} />
          <.check />
        <% true -> %>
          <label class="switch flex-item-no-shrink">
            <input
              type="checkbox"
              name="user_ids[]"
              value={@user.id}
              class="switch__input"
              checked={@selected}
            />
            <span class="switch__btn round"></span>
            <span class="for-screen-reader">Give {@user.name} access to this room</span>
          </label>
      <% end %>
    </.user_row>
    """
  end
end
