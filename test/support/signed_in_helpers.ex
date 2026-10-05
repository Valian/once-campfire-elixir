defmodule CampfireWeb.SignedInHelpers do
  @moduledoc "Signing in without the password round trip (bcrypt cost 12 is ~250 ms), and cable assertions."
  import Plug.Conn

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias Campfire.Repo

  @doc "A conn whose next request carries a `session_token` cookie for the user (or user id)."
  def sign_in(conn, %User{} = user) do
    session = Accounts.start_session!(user, user_agent: "test", ip_address: "127.0.0.1")

    %{conn | secret_key_base: CampfireWeb.Endpoint.config(:secret_key_base)}
    |> put_resp_cookie("session_token", session.token, sign: true)
    |> Phoenix.ConnTest.recycle()
  end

  def sign_in(conn, user_id), do: sign_in(conn, Repo.get!(User, user_id))

  @doc "Subscribes the test process to an (unsigned) cable stream, as a socket would."
  def subscribe_stream(stream), do: CampfireWeb.Cable.subscribe(CampfireWeb.Cable.topic(stream))

  @doc "Asserts a broadcast on `stream` arrived and matches `payload` once JSON-decoded."
  defmacro assert_cable(stream, payload) do
    quote do
      assert_receive {:cable, unquote(stream), json}
      unquote(payload) = Jason.decode!(json)
    end
  end
end
