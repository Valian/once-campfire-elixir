defmodule CampfireWeb.MessagesTestHelpers do
  @moduledoc "Helpers for the message and room page tests."
  import Campfire.DataCase, only: [label: 1]

  alias Campfire.Accounts.User
  alias Campfire.Repo

  def user(name), do: Repo.get!(User, label("users.#{name}"))

  def document(html), do: LazyHTML.from_document(html)
  def fragment(html), do: LazyHTML.from_fragment(html)

  def attr(lazy, name), do: lazy |> LazyHTML.attribute(name) |> List.first()
end
