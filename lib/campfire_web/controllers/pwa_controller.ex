defmodule CampfireWeb.PwaController do
  @moduledoc """
  `/service-worker(.js)` and `/webmanifest(.json)` (no sign-in needed). The service worker
  lets the notifications controller register a push subscription, which is what makes the
  room bell (involvement) load; push messages are never sent.
  """
  use CampfireWeb, :controller

  alias CampfireWeb.{Assets, Components}

  @external_resource service_worker = Path.expand("../../../priv/service-worker.js", __DIR__)
  @service_worker File.read!(service_worker)

  def service_worker(conn, _params) do
    conn
    |> put_resp_content_type("text/javascript")
    |> send_resp(200, @service_worker)
  end

  # Rails renders this through ERB, which HTML-escapes into the JSON (`&amp;` in the logo
  # URL); encoding it as JSON is what was meant.
  def manifest(conn, _params) do
    base = CampfireWeb.Plugs.base_url(conn)
    logo = Components.account_logo_path()
    name = (Campfire.Accounts.account() || %{name: "Campfire"}).name

    manifest =
      Jason.OrderedObject.new(
        name: name,
        icons: [
          Jason.OrderedObject.new(
            src: Components.account_logo_path(:small),
            type: "image/png",
            sizes: "192x192"
          ),
          Jason.OrderedObject.new(src: logo, type: "image/png", sizes: "512x512"),
          Jason.OrderedObject.new(
            src: logo,
            type: "image/png",
            sizes: "512x512",
            purpose: "maskable"
          )
        ],
        start_url: "/",
        display: "standalone",
        scope: "/",
        description: "A chat app from the makers of Basecamp and HEY.",
        categories: ["social", "business", "productivity"],
        theme_color: "#ffffff",
        background_color: "#ffffff",
        shortcuts: [
          Jason.OrderedObject.new(
            name: "New chat room",
            description: "Open Campfire and start a new chat room",
            url: "rooms/opens/new",
            icons: [%{src: base <> Assets.path("add.svg"), sizes: "any"}]
          ),
          Jason.OrderedObject.new(
            name: "My profile",
            description: "Open Campfire and view your profile",
            url: "/users/me/profile",
            icons: [%{src: base <> Assets.path("person.svg"), sizes: "any"}]
          )
        ],
        screenshots:
          for {file, label} <- [
                {"android-chat", "Campfire is an installable, self-hosted group chat system."},
                {"android-sidebar",
                 "Easily invite people. Make rooms. @mentions, DMs, and mobile support."},
                {"android-dark-mode", "Full support for dark mode, customizable to your brand."}
              ] do
            Jason.OrderedObject.new(
              src: base <> Assets.path("screenshots/#{file}.png"),
              sizes: "1080x2400",
              form_factor: "narrow",
              label: label
            )
          end
      )

    conn
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(200, Jason.encode_to_iodata!(manifest))
  end
end
