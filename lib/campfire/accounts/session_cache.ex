defmodule Campfire.Accounts.SessionCache do
  @moduledoc """
  ETS cache of `session token => {session, user}`: the lookup runs on every request and every
  cable connect. Entries are dropped on sign-out (`delete/1`) and whenever a user row changes
  (`forget_user/1`); anything that updates `users` must call the latter.
  """
  use GenServer

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def fetch(token, fun) do
    case :ets.lookup(@table, token) do
      [{^token, session, user}] ->
        {session, user}

      [] ->
        with {session, user} <- fun.() do
          put(session, user)
          {session, user}
        end
    end
  end

  def put(session, user), do: :ets.insert(@table, {session.token, session, user})

  def delete(token), do: :ets.delete(@table, token)

  def forget_user(user_id) do
    :ets.select_delete(@table, [{{:_, :_, %{id: user_id}}, [], [true]}])
    :ok
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
