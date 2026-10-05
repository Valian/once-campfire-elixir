defmodule CampfireWeb.Router do
  use CampfireWeb, :router

  import CampfireWeb.Plugs
  import CampfireWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :accept_authenticity_token
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_version_headers
    plug :block_banned_ip
    plug :assign_turbo_frame
    plug :fetch_current_user
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/", CampfireWeb do
    pipe_through :browser

    get "/session/new", SessionController, :new
    post "/session", SessionController, :create
  end

  # Active Storage files: signed, public bearer URLs, as in Rails (no session needed).
  scope "/rails/active_storage", CampfireWeb do
    for prefix <- ["/blobs/redirect", "/blobs/proxy", "/blobs"] do
      get "#{prefix}/:signed_id/*filename", ActiveStorageController, :blob
    end

    for prefix <- ["/representations/redirect", "/representations/proxy", "/representations"] do
      get "#{prefix}/:signed_blob_id/:variation_key/*filename",
          ActiveStorageController,
          :representation
    end
  end

  scope "/", CampfireWeb do
    pipe_through [:browser, :authenticated]

    get "/", WelcomeController, :show
    delete "/session", SessionController, :delete

    # Messages. `/rooms/:id` matches any segment: room routes with literal segments
    # (`/rooms/opens/...`) must come before it.
    get "/rooms/:id", RoomController, :show
    get "/rooms/:room_id/@:message_id", RoomController, :show
    get "/rooms/:room_id/refresh", RefreshController, :show
    get "/rooms/:room_id/messages", MessageController, :index
    post "/rooms/:room_id/messages", MessageController, :create
    get "/rooms/:room_id/messages/:id", MessageController, :show
    get "/rooms/:room_id/messages/:id/edit", MessageController, :edit
    patch "/rooms/:room_id/messages/:id", MessageController, :update
    put "/rooms/:room_id/messages/:id", MessageController, :update
    delete "/rooms/:room_id/messages/:id", MessageController, :destroy

    get "/messages/:message_id/boosts", BoostController, :index
    get "/messages/:message_id/boosts/new", BoostController, :new
    post "/messages/:message_id/boosts", BoostController, :create
    delete "/messages/:message_id/boosts/:id", BoostController, :destroy
  end
end
