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

  # The ping autocomplete asks for JSON (`Accept: application/json`).
  pipeline :browser_or_json do
    plug :accepts, ["html", "json"]
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

    get "/service-worker", PwaController, :service_worker
    get "/service-worker.js", PwaController, :service_worker
    get "/webmanifest", PwaController, :manifest
    get "/webmanifest.json", PwaController, :manifest

    get "/account/logo", AccountLogoController, :show

    # Out of scope (SPEC §16).
    get "/first_run", StubController, :first_run
    get "/join/:join_code", StubController, :not_found
    get "/qr_code/:id", StubController, :not_found
  end

  scope "/", CampfireWeb do
    pipe_through [:browser_or_json, :authenticated]

    get "/autocompletable/users", AutocompletableUserController, :index
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

    # Out of scope (SPEC §16); `/rooms/:id/settings` is a 404 in Rails too.
    get "/account/edit", StubController, :not_found
    get "/rooms/:room_id/settings", StubController, :not_found
    post "/unfurl_link", StubController, :no_content

    get "/rooms", RoomController, :index

    # Room forms come before the room page's `/rooms/:id` routes (`/rooms/opens/new` …).
    scope "/rooms", Rooms do
      get "/opens/new", OpenController, :new
      post "/opens", OpenController, :create
      get "/opens/:id", OpenController, :show
      get "/opens/:id/edit", OpenController, :edit
      patch "/opens/:id", OpenController, :update
      put "/opens/:id", OpenController, :update

      get "/closeds/new", ClosedController, :new
      post "/closeds", ClosedController, :create
      get "/closeds/:id", ClosedController, :show
      get "/closeds/:id/edit", ClosedController, :edit
      patch "/closeds/:id", ClosedController, :update
      put "/closeds/:id", ClosedController, :update

      get "/directs/new", DirectController, :new
      post "/directs", DirectController, :create
      get "/directs/:id/edit", DirectController, :edit
      delete "/directs/:id", DirectController, :delete

      get "/:room_id/involvement", InvolvementController, :show
      put "/:room_id/involvement", InvolvementController, :update
      patch "/:room_id/involvement", InvolvementController, :update
    end

    get "/searches", SearchController, :index
    post "/searches", SearchController, :create
    delete "/searches/clear", SearchController, :clear

    # `:user_id` is "me" in every link and ignored: these act on the current user.
    get "/users/:user_id/sidebar", SidebarController, :show
    get "/users/:user_id/profile", ProfileController, :show
    patch "/users/:user_id/profile", ProfileController, :update
    put "/users/:user_id/profile", ProfileController, :update
    get "/users/:user_id/push_subscriptions", PushSubscriptionController, :index
    post "/users/:user_id/push_subscriptions", PushSubscriptionController, :create
    delete "/users/:user_id/push_subscriptions/:id", PushSubscriptionController, :delete

    get "/users/:avatar_token/avatar", AvatarController, :show
    delete "/users/:user_id/avatar", AvatarController, :delete
    post "/users/:user_id/ban", UserController, :ban
    delete "/users/:user_id/ban", UserController, :unban
    get "/users/:id", UserController, :show

    # Messages. `/rooms/:id` matches any segment, so it comes after the room forms above.
    get "/rooms/:id", RoomController, :show
    delete "/rooms/:id", RoomController, :delete
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
