defmodule CampfireWeb.SignedInHelpers do
  @moduledoc "Signing in without the password round trip (bcrypt cost 12 is ~250 ms)."
  import Plug.Conn

  alias Campfire.Accounts
  alias Campfire.Repo

  @doc "A conn whose next request carries a `session_token` cookie for `user_id`."
  def sign_in(conn, user_id) do
    user = Repo.get!(Accounts.User, user_id)
    session = Accounts.start_session!(user, user_agent: "test", ip_address: "127.0.0.1")

    %{conn | secret_key_base: CampfireWeb.Endpoint.config(:secret_key_base)}
    |> put_resp_cookie("session_token", session.token, sign: true)
    |> Phoenix.ConnTest.recycle()
  end

  @doc "Subscribes the test process to a cable stream (the `CampfireWeb.Cable` stub's topic)."
  def subscribe_stream(stream), do: Phoenix.PubSub.subscribe(Campfire.PubSub, "cable:" <> stream)
end
