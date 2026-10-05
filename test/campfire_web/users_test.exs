defmodule CampfireWeb.UsersTest do
  use CampfireWeb.ConnCase

  import CampfireWeb.SignedInHelpers
  import Ecto.Query, only: [from: 2]

  alias Campfire.Accounts.{Ban, Session, User}
  alias Campfire.Push.Subscription
  alias Campfire.Repo

  @david 127_326_141
  @kevin 712_064_548
  @jz 773_523_953
  @mallory 773_523_955
  @rita 773_523_954
  @bender 394_959_859

  setup %{conn: conn} do
    {:ok, conn: sign_in(conn, @david)}
  end

  describe "user page" do
    test "as an administrator: email, ping, sign-in link, ban", %{conn: conn} do
      doc = conn |> get("/users/#{@jz}") |> html_response(200) |> LazyHTML.from_document()
      assert doc |> LazyHTML.query("h1") |> LazyHTML.text() == "JZ"
      assert doc |> LazyHTML.query("a[href='mailto:jz@37signals.com']") |> Enum.count() == 1

      assert doc
             |> LazyHTML.query("form[action='/rooms/directs?user_ids%5B%5D=#{@jz}']")
             |> Enum.count() == 1

      assert doc |> LazyHTML.query("#session_transfer_url") |> Enum.count() == 1

      assert doc |> LazyHTML.query("form[action='/users/#{@jz}/ban'] button") |> LazyHTML.text() =~
               "Ban JZ"
    end

    test "as a member: no email, no ban", %{conn: conn} do
      doc =
        conn
        |> sign_in(@kevin)
        |> get("/users/#{@jz}")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("a[href^='mailto:']") |> Enum.count() == 0
      assert doc |> LazyHTML.query("form[action$='/ban']") |> Enum.count() == 0
    end

    test "banned, deactivated, bot", %{conn: conn} do
      banned = conn |> get("/users/#{@mallory}") |> html_response(200)
      assert banned =~ ~s(class="flex flex-column gap banned")
      assert banned =~ "Remove ban"

      assert conn |> get("/users/#{@rita}") |> html_response(200) =~
               "Rita Lopez is no longer on this account"

      assert conn |> get("/users/#{@bender}") |> html_response(200) =~
               ~s(class="btn btn--primary full-width txt--large")
    end

    test "unknown users are 404", %{conn: conn} do
      assert get(conn, "/users/1").status == 404
    end

    test "ban and unban", %{conn: conn} do
      Repo.insert!(%Session{
        user_id: @jz,
        token: "jz-token-123456789012345",
        ip_address: "8.8.8.8",
        last_active_at: DateTime.utc_now()
      })

      Repo.insert!(%Session{
        user_id: @jz,
        token: "jz-token-223456789012345",
        ip_address: "10.0.0.1",
        last_active_at: DateTime.utc_now()
      })

      assert redirected_to(post(conn, "/users/#{@jz}/ban")) == "/users/#{@jz}"
      assert Repo.get!(User, @jz).status == :banned
      assert Repo.get_by(Ban, user_id: @jz, ip_address: "8.8.8.8")
      refute Repo.get_by(Ban, user_id: @jz, ip_address: "10.0.0.1")
      refute Repo.get_by(Session, user_id: @jz)

      delete(recycle(conn), "/users/#{@jz}/ban")
      assert Repo.get!(User, @jz).status == :active
      refute Repo.get_by(Ban, user_id: @jz)
    end

    test "members can't ban", %{conn: conn} do
      assert post(sign_in(conn, @kevin), "/users/#{@jz}/ban").status == 403
    end
  end

  describe "profile" do
    test "the form and the room notifications", %{conn: conn} do
      doc = conn |> get("/users/me/profile") |> html_response(200) |> LazyHTML.from_document()
      assert doc |> LazyHTML.query("input#user_name") |> LazyHTML.attribute("value") == ["David"]

      assert doc
             |> LazyHTML.query("form[enctype='multipart/form-data'] input[name='user[avatar]']")
             |> Enum.count() == 2

      assert doc |> LazyHTML.query(".avatar__delete-btn") |> Enum.count() == 0

      frames = doc |> LazyHTML.query(".membership-item turbo-frame") |> LazyHTML.attribute("id")
      # All rooms, invisible ones too: shared by name, then directs.
      assert "involvement_rooms_open_699448327" in frames
      assert List.last(frames) =~ "involvement_rooms_direct_"
      assert doc |> LazyHTML.query(".membership-item strong") |> LazyHTML.text() =~ "Jason"
    end

    test "PWA help depends on the browser", %{conn: conn} do
      safari =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

      chrome =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

      assert conn
             |> put_req_header("user-agent", safari)
             |> get("/users/me/profile")
             |> html_response(200) =~ "Add to Dock…"

      refute conn
             |> put_req_header("user-agent", chrome)
             |> get("/users/me/profile")
             |> html_response(200) =~ "pwa__instructions"
    end

    test "update name, bio and password", %{conn: conn} do
      conn =
        patch(conn, "/users/me/profile", %{
          "user" => %{
            "name" => "Dave",
            "bio" => "Hi",
            "password" => "newpassword1",
            "email_address" => ""
          }
        })

      assert redirected_to(conn) == "/users/me/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :notice) == "✓"

      user = Repo.get!(User, @david)
      assert {user.name, user.bio, user.email_address} == {"Dave", "Hi", "david@37signals.com"}
      assert Bcrypt.verify_pass("newpassword1", user.password_digest)

      # The session cache saw the change.
      assert get(recycle(conn), "/users/me/profile") |> html_response(200) =~ ~s(content="Dave")
    end

    test "a taken email is refused", %{conn: conn} do
      conn =
        patch(conn, "/users/me/profile", %{"user" => %{"email_address" => "jz@37signals.com"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :alert)
      assert Repo.get!(User, @david).email_address == "david@37signals.com"
    end
  end

  describe "autocompletable users" do
    test "prompt items for a room's members, filtered", %{conn: conn} do
      html =
        conn |> get("/autocompletable/users?room_id=654632876&filter=j") |> html_response(200)

      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query("lexxy-prompt-item") |> LazyHTML.attribute("search") == [
               "Jason",
               "JZ"
             ]

      assert html =~ ~s(<template type="editor">)
      assert html =~ ~s(<span class="mention" sgid=")
      refute html =~ "<html"
    end

    test "JSON for the ping autocomplete", %{conn: conn} do
      users =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/autocompletable/users?query=Kev")
        |> json_response(200)

      assert [
               %{
                 "name" => "Kevin",
                 "value" => @kevin,
                 "avatar_url" => "http://www.example.com/users/" <> _,
                 "sgid" => _
               }
             ] = users
    end

    test "a room the user isn't in is 404", %{conn: conn} do
      assert get(sign_in(conn, 773_523_958), "/autocompletable/users?room_id=654632876").status ==
               404
    end
  end

  describe "push subscriptions and PWA" do
    test "stores a subscription once", %{conn: conn} do
      body = %{
        "push_subscription" => %{
          "endpoint" => "https://fcm.googleapis.com/fcm/send/abc",
          "p256dh_key" => "k",
          "auth_key" => "a"
        }
      }

      assert post(conn, "/users/me/push_subscriptions", body).status == 200
      assert post(conn, "/users/me/push_subscriptions", body).status == 200

      assert Repo.aggregate(
               from(s in Subscription,
                 where: s.endpoint == "https://fcm.googleapis.com/fcm/send/abc"
               ),
               :count
             ) == 1

      bad = put_in(body, ["push_subscription", "endpoint"], "http://evil.example/x")
      assert post(conn, "/users/me/push_subscriptions", bad).status == 422
    end

    test "service worker and manifest need no sign-in" do
      sw = get(build_conn(), "/service-worker.js")
      assert sw.status == 200
      assert sw.resp_body =~ "addEventListener(\"push\""

      manifest = get(build_conn(), "/webmanifest.json") |> response(200) |> Jason.decode!()
      assert manifest["name"] == "37signals"
      assert [%{"sizes" => "192x192"} | _] = manifest["icons"]
    end
  end
end
