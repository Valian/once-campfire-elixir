defmodule CampfireWeb.RoomHTML do
  use CampfireWeb, :html

  alias Campfire.Rooms.Room
  alias Campfire.Signing
  alias CampfireWeb.NotificationsHelp

  embed_templates "room_html/*"

  @doc "The Turbo stream a room's messages are broadcast on: `{room gid param}:messages`."
  def messages_stream(%Room{} = room),
    do: Signing.gid_param(Room.class_name(room), room.id) <> ":messages"

  def dom_id(%Room{} = room, prefix), do: "#{prefix}_#{Room.param_key(room)}_#{room.id}"

  def room_kind(%Room{} = room), do: if(Room.direct?(room), do: "Ping", else: "room")

  @doc "The join link (`join_url(account.join_code)`)."
  def join_url(base_url, account), do: "#{base_url}/join/#{account.join_code}"

  @doc "The viewer's avatar inside the pending-message `<script>` template (no components there)."
  def pending_avatar(user),
    do: {:safe, CampfireWeb.MessageComponents.to_iodata(&avatar/1, %{user: user})}

  @doc "`rooms/show/_invitation` with `accounts/_invite`: shown in the original room until it pages."
  attr :account, :map, required: true
  attr :base_url, :string, required: true
  attr :current_user, :map, required: true

  def invitation(assigns) do
    assigns = assign(assigns, :url, join_url(assigns.base_url, assigns.account))

    ~H"""
    <div id="system_welcome" class="message message--formatted txt-align-center center">
      <div class="message__body center">
        <div class="message__body-content position-relative">
          <.account_logo class="center margin-block-end txt-large" />
          <div class="flex align-center gap">
            <div class="system-welcome--translation">
              <.translation_button key={:invite_message} />
            </div>
            <p>
              <strong>Welcome to Campfire</strong><br />
              To invite people to chat, share the join link below.
            </p>
          </div>

          <div class="flex flex-column align-center gap">
            <label class="flex flex-column gap full-width" style="--row-gap: 0.5em">
              <strong id="invite_label" class="invite-label">Share to invite more people</strong>
              <span class="flex align-center gap input input--actor fill-white">
                <.image src="person-add.svg" aria-hidden="true" size="20" class="colorize--black" />
                <input
                  type="text"
                  class="input"
                  id="invite_url"
                  value={@url}
                  aria-labelledby="invite_label"
                  readonly
                />
              </span>
            </label>

            <div class="flex align-center gap">
              <a
                class="btn"
                data-lightbox-target="image"
                data-action="lightbox#open"
                data-lightbox-url-value={"/qr_code/#{Base.url_encode64(@url)}"}
                href={"/qr_code/#{Base.url_encode64(@url)}"}
              >
                <span class="for-screen-reader">Show join link QR code</span>
                <.image src="qr-code.svg" aria-hidden="true" size="20" class="colorize--black" />
              </a>

              <button
                class="btn"
                data-controller="copy-to-clipboard"
                data-action="copy-to-clipboard#copy"
                data-copy-to-clipboard-success-class="btn--success"
                data-copy-to-clipboard-content-value={@url}
              >
                <span class="for-screen-reader">Copy join link</span>
                <.image src="copy-paste.svg" aria-hidden="true" size="20" class="colorize--black" />
              </button>

              <button
                class="btn"
                hidden="hidden"
                data-controller="web-share"
                data-action="web-share#share"
                data-web-share-url-value={@url}
                data-web-share-text-value="Hit this link to join me in Campfire and start chatting."
                data-web-share-title-value="Link to join Campfire"
              >
                <span class="for-screen-reader">Share join link</span>
                <.image src="share.svg" aria-hidden="true" size="20" class="colorize--black" />
              </button>

              <form
                :if={Campfire.Accounts.User.administrator?(@current_user)}
                class="button_to"
                method="post"
                action="/account/join_code"
              >
                <button class="btn btn--regenerate" type="submit">
                  <.image src="refresh.svg" aria-hidden="true" size="20" class="colorize--black" />
                  <span class="for-screen-reader">Regenerate join link</span>
                </button><.csrf_input />
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
