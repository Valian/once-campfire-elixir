defmodule CampfireWeb.PushSubscriptionHTML do
  @moduledoc "`users/push_subscriptions/index` (a developer page; no test-notification button)."
  use CampfireWeb, :html

  def index(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      turbo_frame={@turbo_frame}
      title="Push notification subscriptions"
    >
      <section class="panel panel--wide flex flex-column gap">
        <h1 class="txt-align-center txt-large margin-none">Push Notification Subscriptions</h1>
        <div class="pad-inline fill-shade border-radius" id="push_subscriptions">
          <menu class="pad flex flex-column gap">
            <li :for={s <- @subscriptions} class="flex flex-column margin-none membership-item">
              <span class="overflow-ellipsis txt-primary txt-undecorated">
                <strong>{s.user_agent}</strong><br />
              </span>

              <span class="flex align-start gap txt-small">
                <span>{s.endpoint}</span>

                <form class="button_to" method="post" action={"/users/me/push_subscriptions/#{s.id}"}>
                  <input
                    type="hidden"
                    name="_method"
                    value="delete"
                  /><button class="btn btn--negative" type="submit">
                    <.image src="minus.svg" size="20" aria-hidden="true" />
                    <span class="for-screen-reader">Delete subscription</span>
                  </button><.csrf_input />
                </form>
              </span>
            </li>
          </menu>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
