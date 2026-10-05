defmodule CampfireWeb.UserComponents do
  @moduledoc "Pieces of the user and profile pages: back link, sign-in transfer link, PWA help."
  use CampfireWeb, :html

  alias Campfire.Signing
  alias CampfireWeb.Platform

  @doc "Rails `link_back`: to the referrer, unless it's this very page."
  attr :to, :string, required: true

  def link_back(assigns) do
    ~H"""
    <a class="btn" href={@to}><.image src="arrow-left.svg" size="20" aria-hidden="true" /><span class="for-screen-reader">Go Back</span></a>
    """
  end

  def back_url(conn) do
    case Plug.Conn.get_req_header(conn, "referer") do
      [referer | _] -> if referer == current_url(conn), do: "/", else: referer
      [] -> "/"
    end
  end

  defp current_url(conn) do
    url = CampfireWeb.Plugs.base_url(conn) <> conn.request_path
    if conn.query_string == "", do: url, else: url <> "?" <> conn.query_string
  end

  @doc """
  `users/profiles/_transfer`: a sign-in link for another device (Rails
  `user.signed_id(purpose: :transfer, expires_in: 4.hours)`), with QR, copy and share buttons.
  """
  attr :user, :any, required: true
  attr :current_user, :any, required: true
  attr :base_url, :string, required: true

  def transfer(assigns) do
    expires_at = DateTime.add(DateTime.utc_now(), 4 * 3600, :second)

    token =
      assigns.user.id
      |> Signing.envelope("user/transfer", expires_at)
      |> Signing.sign("active_record/signed_id", :sha256, :url_safe_nopad)

    url = "#{assigns.base_url}/session/transfers/#{token}"
    assigns = assign(assigns, url: url, qr_path: "/qr_code/#{Base.url_encode64(url)}")

    ~H"""
    <fieldset>
      <legend class="gap">
        <.image src="laptop.svg" size="36" aria-hidden="true" class="colorize--black" />
        <.image src="transfer.svg" size="36" aria-hidden="true" class="colorize--black" />
        <.image src="mobile-phone.svg" size="36" aria-hidden="true" class="colorize--black" />
      </legend>

      <div class="flex flex-column gap">
        <%= if @current_user.id != @user.id do %>
          <div class="flex align-center gap justify-center">
            <.image
              src="crown.svg"
              size="16"
              aria-hidden="true"
              class="flex-item-no-shrink colorize--black"
            />
            <label for="session_transfer_url">Share to get them back into their account</label>
          </div>
        <% else %>
          <label for="session_transfer_url" class="for-screen-reader">
            Use this link to login automatically on another device
          </label>
        <% end %>

        <input type="text" class="input" value={@url} id="session_transfer_url" readonly />

        <div class="flex align-center center gap">
          <a
            class="btn"
            data-lightbox-target="image"
            data-action="lightbox#open"
            data-lightbox-url-value={@qr_path}
            href={@qr_path}
          >
            <span class="for-screen-reader">Show auto-login QR code</span>
            <.image src="qr-code.svg" size="20" aria-hidden="true" class="colorize--black" />
          </a>

          <button
            class="btn"
            data-controller="copy-to-clipboard"
            data-action="copy-to-clipboard#copy"
            data-copy-to-clipboard-success-class="btn--success"
            data-copy-to-clipboard-content-value={@url}
          >
            <span class="for-screen-reader">Copy auto-login link</span>
            <.image
              src="copy-paste.svg"
              size="20"
              aria-hidden="true"
              class="flex-item-no-shrink colorize--black"
            />
          </button>

          <button
            class="btn"
            hidden
            data-controller="web-share"
            data-action="web-share#share"
            data-web-share-url-value={@url}
            data-web-share-text-value="This is your own private sign-in URL, DO NOT SHARE IT. Use it to sign-in on another device or if you get locked out."
            data-web-share-title-value="Your sign-in link"
          >
            <span class="for-screen-reader">Share auto-login link</span>
            <.image
              src="share.svg"
              size="20"
              aria-hidden="true"
              class="flex-item-no-shrink colorize--black"
            />
          </button>
        </div>
      </div>
    </fieldset>
    """
  end

  @doc """
  `pwa/_install_instructions`. NOTE: the room page's bell dialog renders this too, with the
  other PWA help partials; dedupe at merge.
  """
  attr :platform, Platform, required: true

  def install_instructions(assigns) do
    p = assigns.platform

    assigns =
      assign(assigns,
        show: not (Platform.chrome?(p) or (Platform.firefox?(p) and not p.android?)),
        case:
          cond do
            Platform.edge?(p) -> :edge
            Platform.chrome?(p) and p.android? -> :chrome_android
            Platform.firefox?(p) and p.android? -> :firefox_android
            Platform.safari?(p) and Platform.desktop?(p) -> :safari_desktop
            (Platform.safari?(p) or Platform.chrome?(p)) and p.ios? -> :ios
            true -> :other
          end
      )

    ~H"""
    <details
      :if={@show}
      class="notifications-help pwa__instructions hide-in-pwa"
      data-controller="pwa-install"
      data-pwa-install-prompting-class="pwa--can-install"
      data-notifications-target="details"
    >
      <summary class="btn">
        <.image src="external/install.svg" size="20" aria-hidden="true" />
        <strong>Install Campfire as a web app.</strong>
        <.image src="disclosure.svg" size="10" aria-hidden="true" class="disclosure" />
      </summary>

      <%= case @case do %>
        <% :edge -> %>
          <ol>
            <li>
              Click <em><.image
                  src="external/install-edge.svg"
                  size="16"
                  alt="the app available - install Campfire chat button"
                /></em>in the address bar.
            </li>
            <li>Click <em>Install</em>.</li>
          </ol>
        <% :chrome_android -> %>
          <ol>
            <li>
              Tap the <em><.image src="menu-dots-vertical.svg" size="16" alt="More options" /></em>
              menu button.
            </li>
            <li>Tap <em>Install app</em> in the menu.</li>
          </ol>
        <% :firefox_android -> %>
          <ol>
            <li>
              Tap the <em><.image src="menu-dots-vertical.svg" size="16" alt="More options" /></em>
              menu button.
            </li>
            <li>Tap <em>Install</em> in the menu.</li>
          </ol>
        <% :safari_desktop -> %>
          <ol>
            <li>Click <em>File</em> in the top left.</li>
            <li>Click <em>Add to Dock…</em>.</li>
          </ol>
        <% :ios -> %>
          <p>
            To receive push notifications in {Platform.browser_name(@platform)} for {Platform.os_name(
              @platform
            )}, you must install Campfire as a web app.
          </p>
          <ol>
            <li>Tap <em><.image src="external/share.svg" size="20" alt="the share button" /></em></li>
            <li>Tap <em>Add to Home Screen</em>.</li>
          </ol>
        <% :other -> %>
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
end
