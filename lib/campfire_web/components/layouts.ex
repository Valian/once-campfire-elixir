defmodule CampfireWeb.Layouts do
  @moduledoc """
  The page layout (port of Rails' `layouts/application.html.erb`) as one component. Pages wrap
  their content in it and fill Rails' `content_for` blocks through slots:

      <Layouts.app flash={@flash} current_user={@current_user} turbo_frame={@turbo_frame}
                   title="Search" body_class="sidebar searches">
        <:head><meta name="current-room-id" content={@room.id} /></:head>
        <:nav>…</:nav>
        main content…
        <:footer>…</:footer>
        <:sidebar>…</:sidebar>
      </Layouts.app>

  When the request came from a `<turbo-frame>` (`@turbo_frame` set), the minimal frame layout
  is rendered instead, as turbo-rails does; nav/footer/sidebar are dropped.
  """
  use CampfireWeb, :html

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias CampfireWeb.Assets

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_user, User, default: nil
  attr :turbo_frame, :string, default: nil, doc: "the Turbo-Frame request header"
  attr :title, :string, default: "Campfire"
  attr :body_class, :string, default: nil
  slot :inner_block, required: true
  slot :head
  slot :nav
  slot :footer
  slot :sidebar

  def app(%{turbo_frame: frame} = assigns) when is_binary(frame), do: frame(assigns)
  def app(assigns), do: application(assigns)

  defp body_class(body_class, current_user) do
    [
      body_class,
      current_user && User.administrator?(current_user) && "admin",
      Accounts.account_logo?() && "account-has-logo"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp custom_styles do
    case Accounts.account() do
      %{custom_styles: styles} when is_binary(styles) -> styles
      _ -> nil
    end
  end
end
