defmodule CampfireWeb.MessagesTestHelpers do
  @moduledoc "Helpers for the message and room page tests."
  import Campfire.DataCase, only: [label: 1]

  alias Campfire.Accounts.User
  alias Campfire.Repo

  def user(name), do: Repo.get!(User, label("users.#{name}"))

  @doc "A conn signed in as `user` (a session row and the signed `session_token` cookie)."
  def log_in(conn, %User{} = user) do
    session = Campfire.Accounts.start_session!(user, user_agent: "test", ip_address: "127.0.0.1")
    conn = %{conn | secret_key_base: CampfireWeb.Endpoint.config(:secret_key_base)}

    conn
    |> Plug.Conn.put_resp_cookie("session_token", session.token, sign: true)
    |> Phoenix.ConnTest.recycle()
  end

  @doc "Subscribes the test process to a cable stream (the stub broadcasts over PubSub)."
  def subscribe(stream), do: Phoenix.PubSub.subscribe(Campfire.PubSub, stream)

  def document(html), do: LazyHTML.from_document(html)
  def fragment(html), do: LazyHTML.from_fragment(html)

  def attr(lazy, name), do: lazy |> LazyHTML.attribute(name) |> List.first()
end
