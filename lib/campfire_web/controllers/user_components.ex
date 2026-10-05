defmodule CampfireWeb.UserComponents do
  @moduledoc "Pieces of the user and profile pages: back link, sign-in transfer link, PWA help."
  use CampfireWeb, :html

  alias Campfire.Signing

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
end
