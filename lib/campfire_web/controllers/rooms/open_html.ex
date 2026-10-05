defmodule CampfireWeb.Rooms.OpenHTML do
  @moduledoc "`rooms/opens/{new,edit,_form,_user}`."
  use CampfireWeb, :html

  import CampfireWeb.Rooms.RoomFormHTML

  def form(assigns) do
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
        action={if @room, do: "/rooms/opens/#{@room.id}", else: "/rooms/opens"}
        method={@room && "patch"}
        name={@name}
        can_administer={@can_administer}
      >
        <.everyone
          open={true}
          type_change_path={
            @can_administer &&
              if(@room, do: "/rooms/closeds/#{@room.id}/edit", else: "/rooms/closeds/new")
          }
        />

        <.filter_search :if={length(@users) > 20} />

        <div data-filter-target="list" contents>
          <.user_row :for={user <- @users} user={user}>
            <.check :if={@can_administer} />
          </.user_row>
        </div>
      </.room_form>
    </.page>
    """
  end
end
