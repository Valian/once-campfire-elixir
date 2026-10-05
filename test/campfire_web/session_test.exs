defmodule CampfireWeb.SessionTest do
  use CampfireWeb.ConnCase

  alias Campfire.Accounts.Session
  alias Campfire.Repo

  test "GET /up needs no session or database", %{conn: conn} do
    conn = get(conn, "/up")
    assert response(conn, 200) =~ "background-color: green"
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "the sign-in page", %{conn: conn} do
    html = conn |> get(~p"/session/new") |> html_response(200)
    assert csrf_meta(html) != ""
    assert [_, css] = Regex.run(~r{href="(/assets/[^"]+\.css)"}, html)
    assert css =~ ~r{^/assets/_reset-\w+\.css$}
    assert html =~ "<strong>37signals</strong>"
    assert html =~ ~s(<meta name="turbo-visit-control" content="reload">)
  end

  test "signed-out visitors are sent to sign in, and back afterwards", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/session/new"

    conn = post(recycle(conn), ~p"/session", credentials())
    assert redirected_to(conn) == ~p"/"
  end

  test "wrong password: 401 and the form again", %{conn: conn} do
    conn = post(conn, ~p"/session", %{credentials() | "password" => "nope"})
    html = html_response(conn, 401)
    assert html =~ "Too many requests or unauthorized."
    assert html =~ ~s(class="panel shake")
  end

  # The loadgen's protocol (SPEC §1.3, trap T3): the cookie jar is frozen after login, so tokens
  # rendered later must verify against cookies from the login response.
  test "login as the loadgen does it, then POST with the frozen jar" do
    new = csrf_conn() |> get(~p"/session/new")
    jar = set_cookies(new)
    token = new |> html_response(200) |> csrf_meta()

    login =
      csrf_conn()
      |> put_req_header("cookie", cookie_header(jar))
      |> post(~p"/session", Map.put(credentials(), "authenticity_token", token))

    assert login.status == 302
    jar = Map.merge(jar, set_cookies(login))
    assert %{"session_token" => _} = jar

    page = csrf_conn() |> put_req_header("cookie", cookie_header(jar)) |> get(~p"/session/new")
    assert get_resp_header(page, "set-cookie") == []
    token = page |> html_response(200) |> csrf_meta()

    assert Repo.aggregate(Session, :count) == 2

    logout =
      csrf_conn()
      |> put_req_header("cookie", cookie_header(jar))
      |> put_req_header("x-csrf-token", token)
      |> post(~p"/session", %{"_method" => "delete"})

    assert redirected_to(logout) == ~p"/"
    assert Repo.aggregate(Session, :count) == 1
  end

  test "a POST without a valid token is refused" do
    assert_error_sent 403, fn -> post(csrf_conn(), ~p"/session", credentials()) end

    assert_error_sent 403, fn ->
      post(csrf_conn(), ~p"/session", Map.put(credentials(), "authenticity_token", "forged"))
    end
  end

  defp credentials,
    do: %{"email_address" => label("emails.david"), "password" => label("passwords.all")}
end
