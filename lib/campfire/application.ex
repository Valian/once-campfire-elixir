defmodule Campfire.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Campfire.Repo,
        Campfire.Repo.Setup,
        replica(),
        {Phoenix.PubSub, name: Campfire.PubSub},
        Campfire.Accounts.SessionCache,
        CampfireWeb.RateLimiter,
        CampfireWeb.MessageRenderer,
        CampfireWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Campfire.Supervisor)
  end

  # In test the replica reads through Campfire.Repo (config/test.exs), so there's nothing to start.
  defp replica do
    if Campfire.Repo.Replica.get_dynamic_repo() == Campfire.Repo.Replica,
      do: Campfire.Repo.Replica
  end

  @impl true
  def config_change(changed, _new, removed) do
    CampfireWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
