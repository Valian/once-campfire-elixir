defmodule CampfireWeb.NotificationsHelp do
  @moduledoc """
  "Notifications aren't allowed" help, per browser and OS: ports of `pwa/_browser_settings`,
  `pwa/_system_settings` and `pwa/_install_instructions`.
  """
  use CampfireWeb, :html

  alias CampfireWeb.Platform

  attr :platform, Platform, required: true
  attr :root_url, :string, required: true

  def help(assigns) do
    assigns = platform_assigns(assigns)

    ~H"""
    <.browser_settings {assigns} />
    <.system_settings {assigns} />
    <.install_instructions {assigns} />
    """
  end

  defp browser_settings(%{platform: p} = assigns) do
    assigns = assign(assigns, :skip?, (p.safari? or p.chrome?) and p.ios?)

    ~H"""
    <details :if={!@skip?} class="notifications-help" data-notifications-target="details">
      <summary class="btn">
        <.image src="external/web.svg" aria-hidden="true" size="20" />
        <strong>Check your {@browser} settings</strong>
        <.image src="disclosure.svg" aria-hidden="true" size="10" class="disclosure" />
      </summary>
      <%= cond do %>
        <% @platform.firefox? and @platform.android? -> %>
          <ol>
            <li>
              Tap <em><.image src="lock.svg" alt="the View site information button" size="20" /></em>
              in the address bar.
            </li>
            <li>Tap <em>Notification</em> to change to <em>Allowed</em>.</li>
          </ol>
        <% @platform.edge? and @desktop? -> %>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for this website.
          </h2>
          <ol>
            <li>
              Click
              <em><.image src="lock.svg" alt="the View site information button" size="20" /></em>
              left of the address bar.
            </li>
            <li>
              Under <em>Permissions for this site &gt; Notifications</em>, choose <em>Allow</em>.
            </li>
          </ol>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for {@browser}.
          </h2>
          <.os_switch_steps windows?={@platform.windows?} browser={@browser} alt="the switch" />
        <% @platform.firefox? and @desktop? -> %>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for this website.
          </h2>
          <ol>
            <li>Click <em>{@browser}</em> in the top left.</li>
            <li>Click <em>Settings…</em>.</li>
            <li>Click <em>Privacy &amp; Security</em> in the sidebar.</li>
            <li>Scroll down to <em>Permissions</em>.</li>
            <li>Click <em>Settings</em> next to <em>Notifications</em>.</li>
            <li>Select <em>Allow</em> next to <em>{@root_url}</em>.</li>
          </ol>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for {@browser}.
          </h2>
          <.os_switch_steps windows?={@platform.windows?} browser={@browser} alt="the toggle button" />
        <% @platform.chrome? and @desktop? -> %>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for this website.
          </h2>
          <ol>
            <li>
              Click the
              <em><.image src="external/sliders.svg" alt="View site information" size="20" /></em>
              icon in the address bar.
            </li>
            <li>Click <em>Site Settings</em>.</li>
            <li>Ensure notifications are <em>Allowed</em>.</li>
          </ol>
          <h2 class="txt-normal txt-medium margin-block-start">
            Turn on notifications for {@browser}.
          </h2>
          <.os_switch_steps windows?={@platform.windows?} browser={@browser} alt="the switch" />
        <% @platform.chrome? and @platform.android? -> %>
          <ol>
            <li>
              Tap the <em><.image src="menu-dots-vertical.svg" alt="More options" size="16" /></em>
              menu button.
            </li>
            <li>Tap <em>Settings</em>.</li>
            <li>Tap <em>Notifications</em>.</li>
            <li>
              Tap <em><.image src="external/switch.svg" alt="the switch" size="22" /></em>
              to <em>Allow {@browser} notifications</em>.
            </li>
            <li>
              Tap <em><.image src="external/switch.svg" alt="the switch" size="22" /></em>
              next to <em>Web apps</em>.
            </li>
            <li>
              Tap
              <em><.image src="notification-bell-alert.svg" alt="the notification bell" size="16" /></em>
              and select <em>Allow</em>.
            </li>
          </ol>
        <% @platform.safari? and @desktop? -> %>
          <ol>
            <li>Click <em>{@browser}</em> in the top left.</li>
            <li>Click <em>Settings…</em>.</li>
            <li>Click the <em>Websites</em> tab.</li>
            <li>Click <em>Notifications</em> in the sidebar.</li>
            <li>Click <em>{@root_url}</em> in the list.</li>
            <li>Select <em>Allow</em>.</li>
          </ol>
        <% true -> %>
          <p>
            Ensure notifications are enabled for <em>{@root_url}</em> in your web browser settings.
          </p>
      <% end %>
    </details>
    """
  end

  attr :windows?, :boolean, required: true
  attr :browser, :string, required: true
  attr :alt, :string, required: true

  defp os_switch_steps(assigns) do
    ~H"""
    <ol>
      <%= if @windows? do %>
        <li>Click <em>Start</em>, then <em>Settings</em>.</li>
        <li>Go to <em>System &gt; Notification</em>.</li>
        <li>
          Click <em><.image src="external/switch.svg" alt={@alt} size="22" /></em> <em>ON</em>
          for {@browser}.
        </li>
      <% else %>
        <li>Click <em aria-label="the Apple menu"></em> in the top left.</li>
        <li>Click <em>System Settings…</em>.</li>
        <li>Click <em>Notifications</em>.</li>
        <li>Click <em>{@browser}</em>.</li>
        <li>
          Click <em><.image src="external/switch.svg" alt="the switch" size="22" /></em>
          to <em>Allow notifications</em>.
        </li>
      <% end %>
    </ol>
    """
  end

  defp system_settings(assigns) do
    ~H"""
    <details class="notifications-help hide-in-browser" data-notifications-target="details">
      <summary class="btn">
        <.image src="external/gear.svg" aria-hidden="true" size="20" />
        <strong>Check your {@platform.os} settings</strong>
        <.image src="disclosure.svg" aria-hidden="true" size="10" class="disclosure" />
      </summary>
      <%= cond do %>
        <% @platform.firefox? and @platform.android? -> %>
          <ol>
            <li>
              Tap the <em><.image src="menu-dots-vertical.svg" alt="More options" size="16" /></em>
              menu button.
            </li>
            <li>Tap <em>Settings</em>.</li>
            <li>Tap <em>Notifications</em>.</li>
            <li>
              Tap <em><.image src="external/switch.svg" alt="the toggle button" size="22" /></em>
              to <em>Allow {@browser} notifications</em>.
            </li>
          </ol>
        <% (@platform.edge? and @desktop?) or ((@platform.firefox? or @platform.chrome?) and @desktop? and @platform.windows?) -> %>
          <ol>
            <li>Click <em>Start</em>, then <em>Settings</em>.</li>
            <li>Go to <em>System &gt; Notification</em>.</li>
            <li>
              Click <em><.image src="external/switch.svg" alt="the toggle button" size="22" /></em>
              <em>ON</em> for Campfire.
            </li>
          </ol>
        <% ((@platform.firefox? or @platform.chrome?) and @desktop?) or (@platform.safari? and @desktop?) -> %>
          <ol>
            <li>Click <em aria-label="the Apple menu"></em> in the top left.</li>
            <li>Click <em>System Settings…</em>.</li>
            <li>Click <em>Notifications</em>.</li>
            <li>Click <em>Campfire</em>.</li>
            <li>
              Click
              <em><.image src="external/switch.svg" alt="the allow notifications switch" size="22" /></em>
              to <em>Allow notifications</em>.
            </li>
          </ol>
        <% (@platform.safari? or @platform.chrome?) and @platform.ios? -> %>
          <ol>
            <li>
              Open the <em><.image src="external/gear.svg" aria-hidden="true" size="20" /></em>
              Settings app.
            </li>
            <li>Scroll to and tap <em>Campfire</em>.</li>
            <li>Tap <em>Notifications</em>.</li>
            <li>
              Tap
              <em><.image
                src="external/switch.svg"
                alt="the allow notifications switch button"
                size="22"
              /></em>
              to <em>Allow Notifications</em>.
            </li>
          </ol>
        <% @platform.chrome? and @platform.android? -> %>
          <ol>
            <li>
              Open the <em><.image src="external/gear.svg" aria-hidden="true" size="20" /></em>
              Settings app.
            </li>
            <li>Tap <em>Notifications</em>.</li>
            <li>Tap <em>App notifications</em>.</li>
            <li>Scroll to <em>Campfire</em>.</li>
            <li>
              Tap <em><.image src="external/switch.svg" alt="the switch" size="22" /></em>
              to <em>Allow Notifications</em>.
            </li>
          </ol>
        <% true -> %>
          <p>Ensure notifications are allowed for {@browser} in your system settings.</p>
      <% end %>
    </details>
    """
  end

  @doc "`pwa/_install_instructions` alone (the profile page shows it too)."
  attr :platform, Platform, required: true

  def install_instructions(assigns) do
    %{platform: p} = assigns = platform_assigns(assigns)
    assigns = assign(assigns, :skip?, p.chrome? or (p.firefox? and not p.android?))

    ~H"""
    <details
      :if={!@skip?}
      class="notifications-help pwa__instructions hide-in-pwa"
      data-controller="pwa-install"
      data-pwa-install-prompting-class="pwa--can-install"
      data-notifications-target="details"
    >
      <summary class="btn">
        <.image src="external/install.svg" aria-hidden="true" size="20" />
        <strong>Install Campfire as a web app.</strong>
        <.image src="disclosure.svg" aria-hidden="true" size="10" class="disclosure" />
      </summary>
      <%= cond do %>
        <% @platform.edge? -> %>
          <ol>
            <li>
              Click <em><.image src="external/install-edge.svg" alt="the app available - install Campfire chat button" size="16" /></em>in the address bar.
            </li>
            <li>Click <em>Install</em>.</li>
          </ol>
        <% @platform.firefox? and @platform.android? -> %>
          <ol>
            <li>
              Tap the <em><.image src="menu-dots-vertical.svg" alt="More options" size="16" /></em>
              menu button.
            </li>
            <li>Tap <em>Install</em> in the menu.</li>
          </ol>
        <% @platform.safari? and @desktop? -> %>
          <ol>
            <li>Click <em>File</em> in the top left.</li>
            <li>Click <em>Add to Dock…</em>.</li>
          </ol>
        <% @platform.safari? and @platform.ios? -> %>
          <p>
            To receive push notifications in {@browser} for {@platform.os}, you must install Campfire as a web app.
          </p>
          <ol>
            <li>Tap <em><.image src="external/share.svg" alt="the share button" size="20" /></em></li>
            <li>Tap <em>Add to Home Screen</em>.</li>
          </ol>
        <% true -> %>
          <p>
            Some platforms require you to install Campfire as a web app to receive push notifications.
          </p>
      <% end %>
      <div class="margin-block-start txt-align-center pwa__installer">
        <hr class="separator margin-block" />
        <button class="btn btn--reversed center" data-action="pwa-install#promptInstall">
          <.image src="external/install.svg" aria-hidden="true" /> Install now
        </button>
      </div>
    </details>
    """
  end

  defp platform_assigns(%{platform: p} = assigns),
    do: assign(assigns, desktop?: Platform.desktop?(p), browser: String.capitalize(p.browser))
end
