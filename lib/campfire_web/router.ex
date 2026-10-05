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
  end

  scope "/", CampfireWeb do
    pipe_through [:browser_or_json, :authenticated]

    get "/autocompletable/users", AutocompletableUserController, :index
  end

  scope "/", CampfireWeb do
    pipe_through [:browser, :authenticated]

    get "/", WelcomeController, :show
    delete "/session", SessionController, :delete

    # Room forms come before the room page's `/rooms/:id` routes (`/rooms/opens/new` …).
    scope "/rooms", Rooms do
      get "/", RoomController, :index

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

      delete "/:id", RoomController, :delete
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
  end
end
