defmodule CampfireWeb.ComponentsTest do
  use Campfire.DataCase, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]
  import CampfireWeb.Components

  alias Campfire.Accounts.User

  test "avatar links to the user with a Rails-signed avatar URL" do
    assigns = %{user: Repo.get!(User, 149_087_659)}
    html = rendered_to_string(~H"<.avatar user={@user} />")

    assert html =~ ~s(href="/users/149087659")
    assert html =~ ~s(src="/users/#{label("avatar_tokens.jason")}/avatar?v=20260125160000")
    assert html =~ ~s(aria-hidden="true")

    html = rendered_to_string(~H|<.avatar user={@user} img={%{"aria-label" => "Jason boosted 👍"}} />|)
    assert html =~ ~s(aria-label="Jason boosted 👍")
    refute html =~ "aria-hidden"
  end

  test "image resolves the digested asset" do
    assigns = %{}

    assert rendered_to_string(~H|<.image src="add.svg" size="20" aria-hidden="true" />|) ==
             ~s(<img aria-hidden="true" src="/assets/add-f232d8a6.svg" width="20" height="20">)
  end

  test "Turbo frame requests get the frame layout" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <CampfireWeb.Layouts.app flash={%{}} turbo_frame="user_sidebar">frame body</CampfireWeb.Layouts.app>
      """)

    assert html =~ ~s(<meta name="csrf-token")
    assert html =~ "frame body"
    refute html =~ "<!DOCTYPE html>"
  end
end
