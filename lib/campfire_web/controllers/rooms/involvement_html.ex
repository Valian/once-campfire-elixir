defmodule CampfireWeb.Rooms.InvolvementHTML do
  @moduledoc "The notification bell's frame (`rooms/involvements/show`); also on the profile page."
  use CampfireWeb, :html

  alias Campfire.Rooms
  alias Campfire.Rooms.Room

  @labels %{
    mentions: "Notifying about @ mentions",
    everything: "Notifying about all messages",
    nothing: "Notifications are off",
    invisible: "Notifications are off and room invisible in sidebar"
  }

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} turbo_frame={@turbo_frame}>
      <turbo-frame
        data-controller="turbo-frame"
        data-action="notifications:ready@window->turbo-frame#load"
        data-turbo-frame-url-param={"/rooms/#{@room.id}/involvement"}
        id={"involvement_#{Room.param_key(@room)}_#{@room.id}"}
      >
        <.involvement_button room={@room} involvement={@involvement} />
      </turbo-frame>
    </Layouts.app>
    """
  end

  @doc "Rails `button_to_change_involvement`: a PUT to the next involvement in the cycle."
  attr :room, Room, required: true
  attr :involvement, :atom, required: true

  def involvement_button(assigns) do
    assigns =
      assigns
      |> assign(:next, Rooms.next_involvement(assigns.room, assigns.involvement))
      |> assign(:label_id, "involvement_label_#{Room.param_key(assigns.room)}_#{assigns.room.id}")

    ~H"""
    <form
      class="button_to"
      method="post"
      action={"/rooms/#{@room.id}/involvement?involvement=#{@next}"}
    >
      <input
        type="hidden"
        name="_method"
        value="put"
      /><button
        role="checkbox"
        aria-checked="true"
        aria-labelledby={@label_id}
        tabindex="0"
        class={"btn #{@involvement}"}
        type="submit"
      ><.image
        src={"notification-bell-#{@involvement}.svg"}
        size="20"
        aria-hidden="true"
      /><span class="for-screen-reader" id={@label_id}>{label(@involvement)}</span></button><.csrf_input />
    </form>
    """
  end

  defp label(involvement), do: Map.get(@labels, involvement, "")
end
