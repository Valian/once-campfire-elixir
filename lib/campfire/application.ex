defmodule Campfire.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CampfireWeb.Telemetry,
      Campfire.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:campfire, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:campfire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Campfire.PubSub},
      # Start a worker by calling: Campfire.Worker.start_link(arg)
      # {Campfire.Worker, arg},
      # Start to serve requests, typically the last entry
      CampfireWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Campfire.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CampfireWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
