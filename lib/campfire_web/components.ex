defmodule CampfireWeb.Components do
  @moduledoc """
  Function components and helpers shared by pages (ports of Rails view helpers).
  Imported into every `use CampfireWeb, :html` module.
  """
  use Phoenix.Component

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias Campfire.Signing
  alias CampfireWeb.{Assets, Translations}

  @doc """
  Rails `image_tag "x.svg", size: N`: an `<img>` of a logical asset path.

      <.image src="alert.svg" size="24" class="colorize--white" aria-hidden="true" />
  """
  attr :src, :string, required: true, doc: "logical asset path, e.g. `alert.svg`"
  attr :size, :any, default: nil, doc: "sets both width and height"
  attr :rest, :global, include: ~w(alt width height loading)

  def image(assigns) do
    ~H"""
    <img {@rest} src={Assets.path(@src)} width={@size} height={@size} />
    """
  end

  @doc """
  Rails `avatar_tag(user)`: the avatar linking to the user's page. `img` replaces the image's
  default `aria-hidden="true"` (e.g. `img={%{"aria-label" => "…"}}`, `"loading" => "lazy"`).
  """
  attr :user, User, required: true
  attr :img, :map, default: %{"aria-hidden" => "true"}

  def avatar(assigns) do
    ~H"""
    <a
      title={User.title(@user)}
      class="btn avatar"
      data-turbo-frame="_top"
      href={"/users/#{@user.id}"}
    ><img
      {@img}
      src={avatar_path(@user)}
      width="48"
      height="48"
    /></a>
    """
  end

  @doc "`/users/{signed id}/avatar?v={updated_at}`: the token is a Rails signed id (SPEC §3)."
  def avatar_path(%User{id: id, updated_at: updated_at}) do
    "/users/#{avatar_token(id)}/avatar?v=#{Calendar.strftime(updated_at, "%Y%m%d%H%M%S")}"
  end

  def avatar_token(user_id), do: Signing.signed_id(user_id, "user/avatar")

  @doc "Rails `local_datetime_tag`; the `local-time` controller fills it in client-side."
  attr :at, DateTime, required: true
  attr :style, :string, default: "time", values: ~w(time date datetime)
  attr :rest, :global

  def local_datetime(assigns) do
    ~H"""
    <time {@rest} datetime={iso8601(@at)} data-local-time-target={@style}></time>
    """
  end

  @doc "UTC ISO 8601 to the second, as Rails' `Time#iso8601`."
  def iso8601(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  @doc "Milliseconds since the epoch: `data-message-timestamp`, `data-sort-value`, …"
  def epoch_ms(%DateTime{} = at), do: DateTime.to_unix(at, :millisecond)

  @doc "The hidden `authenticity_token` field Rails forms carry."
  def csrf_input(assigns) do
    ~H"""
    <input type="hidden" name="authenticity_token" value={Phoenix.Controller.get_csrf_token()} />
    """
  end

  @doc "`/account/logo?v=…`, cache-busted by the account's `updated_at`."
  def account_logo_path(size \\ nil) do
    version =
      case Accounts.account() do
        %{updated_at: at} -> Calendar.strftime(at, "%Y%m%d%H%M%S")
        nil -> ""
      end

    if size, do: "/account/logo?size=#{size}&v=#{version}", else: "/account/logo?v=#{version}"
  end

  attr :class, :string, default: nil

  def account_logo(assigns) do
    ~H"""
    <figure class={"account-logo avatar #{@class}"}>
      <img
        alt="Account logo"
        src={account_logo_path()}
        width="300"
        height="300"
      />
    </figure>
    """
  end

  @doc "The globe popup listing a field's prompt in several languages."
  attr :key, :atom, required: true

  def translation_button(assigns) do
    assigns = assign(assigns, :translations, Translations.for_key(assigns.key))

    ~H"""
    <details
      class="position-relative"
      data-controller="popup"
      data-action="keydown.esc->popup#close toggle->popup#toggle click@document->popup#closeOnClickOutside"
      data-popup-orientation-top-class="popup-orientation-top"
    >
      <summary class="btn" tabindex="-1">
        <.image src="globe.svg" size="20" aria-hidden="true" class="color-icon" /><span class="for-screen-reader">Translate</span>
      </summary>
      <div class="language-list-menu shadow" data-popup-target="menu">
        <dl class="language-list">
          <%= for {flag, text} <- @translations do %>
            <dt>{flag}</dt>
            <dd class="margin-none">{text}</dd>
          <% end %>
        </dl>
      </div>
    </details>
    """
  end

  @doc "The sidebar frame, lazily loaded from `src` (Rails `sidebar_turbo_frame_tag`)."
  attr :src, :string, default: nil
  slot :inner_block

  def sidebar_frame(assigns) do
    ~H"""
    <turbo-frame
      data-turbo-permanent="true"
      data-controller="rooms-list read-rooms turbo-frame"
      data-rooms-list-unread-class="unread"
      data-action="presence:present@window->rooms-list#read read-rooms:read->rooms-list#read turbo:frame-load->rooms-list#loaded refresh-room:visible@window->turbo-frame#reload"
      id="user_sidebar"
      src={@src}
      target="_top"
    >
      {render_slot(@inner_block)}
    </turbo-frame>
    """
  end

  def version_badge(assigns) do
    ~H"""
    <span class="version-badge">{Application.fetch_env!(:campfire, :app_version)}</span>
    """
  end
end
