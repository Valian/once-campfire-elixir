defmodule CampfireWeb.UserHTML do
  @moduledoc "`users/show` and `users/_ban_button`."
  use CampfireWeb, :html

  import CampfireWeb.UserComponents

  alias Campfire.Accounts.User

  def show(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      turbo_frame={@turbo_frame}
      title={@user.name}
    >
      <:nav>
        <div class="flex-item-justify-start">
          <.link_back to={@back_url} />
        </div>

        <div class="flex align-center gap flex-item-justify-end">
          <a :if={@current_user.id == @user.id} class="btn" href="/users/me/profile">
            <.image src="pencil.svg" aria-hidden="true" />
            <span class="for-screen-reader">Edit my profile</span>
          </a>
        </div>
      </:nav>

      <section class="panel txt-align-center">
        <div class={["flex flex-column gap", @user.status == :banned && "banned"]}>
          <div class="avatar txt-xx-large center" style="background: white">
            <img alt="Profile avatar" class="avatar" src={avatar_path(@user)} />
          </div>

          <%= cond do %>
            <% User.bot?(@user) -> %>
              <div class="pad-double--inline push--inline push--block-start">
                <%= if @user.status == :active do %>
                  <.ping_button user={@user} class="btn btn--primary full-width txt--large" />
                <% else %>
                  <div>{@user.name} is no longer on this account</div>
                <% end %>
              </div>
            <% @user.status == :deactivated -> %>
              <div>
                <h1 class="txt-x-large margin-none">{@user.name}</h1>
                <div>{@user.name} is no longer on this account</div>
              </div>
            <% true -> %>
              <div class="flex flex-column gap" style="--row-gap: calc(var(--block-space) / 3)">
                <h1 class="txt-x-large txt-tight-lines margin-none">{@user.name}</h1>
                <div :if={User.administrator?(@current_user)}>
                  <a href={"mailto:#{@user.email_address}"}>{@user.email_address}</a>
                </div>
                <div>{@user.bio}</div>
              </div>

              <%= if @user.status == :active do %>
                <div class="pad-inline-double margin-inline margin-block-start">
                  <.ping_button user={@user} class="btn btn--reversed full-width txt-large" />
                </div>

                <%= if User.administrator?(@current_user) do %>
                  <hr class="margin-block-start borderless" />
                  <.transfer user={@user} current_user={@current_user} base_url={@base_url} />
                <% end %>
              <% end %>

              <div
                :if={User.administrator?(@current_user) and @current_user.id != @user.id}
                class="margin-block-start"
              >
                <.ban_button user={@user} />
              </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :user, User, required: true
  attr :class, :string, required: true

  defp ping_button(assigns) do
    ~H"""
    <form class="button_to" method="post" action={"/rooms/directs?user_ids%5B%5D=#{@user.id}"}>
      <button
        class={@class}
        type="submit"
      ><.image
        src="messages.svg"
        aria-hidden={not User.bot?(@user) && "true"}
        aria-label={not User.bot?(@user) && "Ping #{@user.name}"}
      /></button><.csrf_input />
    </form>
    """
  end

  attr :user, User, required: true

  defp ban_button(assigns) do
    ~H"""
    <%= if @user.status == :active do %>
      <form class="button_to" method="post" action={"/users/#{@user.id}/ban"}>
        <button
          class="btn full-width"
          data-turbo-confirm="Are you sure you want to ban this user? This will log them out, delete their messages, and block their IP addresses."
          type="submit"
        >
          <.image src="cancel.svg" aria-hidden="true" aria-label={"Ban #{@user.name}"} />
          <span>Ban {@user.name}</span>
        </button><.csrf_input />
      </form>
    <% else %>
      <form class="button_to" method="post" action={"/users/#{@user.id}/ban"}>
        <input
          type="hidden"
          name="_method"
          value="delete"
        /><button
          class="btn btn--negative full-width"
          data-turbo-confirm="Are you sure you want to remove the ban on this user?"
          type="submit"
        >
          <.image src="cancel.svg" aria-hidden="true" aria-label={"Remove Ban #{@user.name}"} />
          <span>Remove ban</span>
        </button><.csrf_input />
      </form>
    <% end %>
    """
  end
end
