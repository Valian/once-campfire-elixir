defmodule CampfireWeb.Cable.Socket do
  @moduledoc """
  One WebSocket connection speaking `actioncable-v1-json` (SPEC §11.1–11.2).

  Commands are handled strictly in arrival order (the process mailbox). Each subscription
  keeps its frame prefix `{"identifier":"…","message":` encoded once at subscribe time, so a
  broadcast (a shared, already-encoded payload binary) becomes `[prefix, payload, "}"]` here:
  no JSON work per recipient.

  State: `user` (`%{id, name}`), `subs` (identifier string → subscription), and `streams`
  (stream → frame prefixes of the subscriptions following it; one PubSub subscription per
  stream however many subscriptions follow it).
  """
  @behaviour WebSock

  require Logger

  alias CampfireWeb.Cable
  alias CampfireWeb.Cable.{Channels, Pinger}

  @welcome ~s({"type":"welcome"})
  @unauthorized ~s({"type":"disconnect","reason":"unauthorized","reconnect":false})
  @remote ~s({"type":"disconnect","reason":"remote","reconnect":true})

  @impl true
  def init(%{user: nil} = state) do
    {:stop, :normal, 1000, [{:text, @unauthorized}], state}
  end

  def init(%{user: user}) do
    Cable.subscribe("user_connections:#{user.id}")
    Cable.subscribe(Pinger.topic())
    {:push, {:text, @welcome}, %{user: user, subs: %{}, streams: %{}}}
  end

  @impl true
  def handle_in({text, opcode: :text}, state) do
    case Jason.decode(text) do
      {:ok, %{"command" => command, "identifier" => identifier} = message}
      when is_binary(identifier) ->
        command(command, identifier, message, state)

      _ ->
        Logger.debug("cable: unprocessable message #{inspect(text)}")
        {:ok, state}
    end
  end

  def handle_in(_binary, state), do: {:ok, state}

  @impl true
  def handle_info({:cable, stream, payload}, state) do
    case state.streams do
      %{^stream => [prefix]} -> {:push, {:text, [prefix, payload, ?}]}, state}
      %{^stream => prefixes} -> {:push, for(p <- prefixes, do: {:text, [p, payload, ?}]}), state}
      _ -> {:ok, state}
    end
  end

  def handle_info({:cable_ping, frame}, state), do: {:push, {:text, frame}, state}

  def handle_info({:disconnect, reconnect: true}, state),
    do: {:stop, :normal, 1000, [{:text, @remote}], state}

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{subs: subs, user: user}) do
    for {_identifier, {sub, _prefix}} <- subs, do: Channels.unsubscribed(sub, user)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Commands

  # A byte-identical identifier that's already subscribed is ignored, as in Rails.
  defp command("subscribe", identifier, _message, state) when is_map_key(state.subs, identifier),
    do: {:ok, state}

  defp command("subscribe", identifier, _message, state) do
    with {:ok, %{} = params} <- Jason.decode(identifier),
         {:ok, sub} <- Channels.subscribe(params, state.user) do
      json = Jason.encode!(identifier)
      prefix = ~s({"identifier":) <> json <> ~s(,"message":)
      state = %{state | subs: Map.put(state.subs, identifier, {sub, prefix})}
      state = Enum.reduce(sub.streams, state, &follow(&2, &1, prefix))
      {:push, {:text, [~s({"identifier":), json, ~s(,"type":"confirm_subscription"})]}, state}
    else
      :reject ->
        json = Jason.encode!(identifier)
        {:push, {:text, [~s({"identifier":), json, ~s(,"type":"reject_subscription"})]}, state}

      _unknown ->
        Logger.debug("cable: can't subscribe to #{identifier}")
        {:ok, state}
    end
  end

  defp command("unsubscribe", identifier, _message, state) do
    case Map.pop(state.subs, identifier) do
      {nil, _} ->
        {:ok, state}

      {{sub, prefix}, subs} ->
        state = Enum.reduce(sub.streams, %{state | subs: subs}, &unfollow(&2, &1, prefix))
        Channels.unsubscribed(sub, state.user)
        {:ok, state}
    end
  end

  defp command("message", identifier, %{"data" => data}, state) when is_binary(data) do
    with {sub, _prefix} <- state.subs[identifier],
         {:ok, %{"action" => action}} when is_binary(action) <- Jason.decode(data) do
      Channels.perform(sub, action, state.user)
    end

    {:ok, state}
  end

  defp command(_command, _identifier, _message, state), do: {:ok, state}

  defp follow(state, stream, prefix) do
    case state.streams do
      %{^stream => prefixes} ->
        %{state | streams: %{state.streams | stream => prefixes ++ [prefix]}}

      _ ->
        Cable.subscribe(Cable.topic(stream))
        %{state | streams: Map.put(state.streams, stream, [prefix])}
    end
  end

  defp unfollow(state, stream, prefix) do
    case List.delete(Map.get(state.streams, stream, []), prefix) do
      [] ->
        Cable.unsubscribe(Cable.topic(stream))
        %{state | streams: Map.delete(state.streams, stream)}

      prefixes ->
        %{state | streams: %{state.streams | stream => prefixes}}
    end
  end
end
