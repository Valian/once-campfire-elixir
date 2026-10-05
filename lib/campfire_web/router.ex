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

  scope "/", CampfireWeb do
    pipe_through [:browser, :authenticated]

    get "/", WelcomeController, :show
    delete "/session", SessionController, :delete
  end
end
