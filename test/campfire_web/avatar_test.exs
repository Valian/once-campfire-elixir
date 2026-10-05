defmodule CampfireWeb.AvatarTest do
  use CampfireWeb.ConnCase

  alias Campfire.Accounts.User
  alias Campfire.{Avatars, Repo}
  alias CampfireWeb.{AvatarCache, Components}

  @david 127_326_141
  @jason 149_087_659
  @bender 394_959_859

  @david_svg """
  <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
    viewBox="0 0 512 512" class="avatar" aria-hidden="true">
    <defs>
      <clipPath id="porthole">
        <circle cx="50%" cy="50%" r="50%" />
      </clipPath>
    </defs>

    <g>
      <rect width="100%" height="100%" rx="50" fill="#736356" />

      <text x="50%" y="50%" fill="#FFFFFF"
        text-anchor="middle" dy="0.35em"

        font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
        font-size="230"
        font-weight="800"
        letter-spacing="-5">
        D
      </text>
    </g>
  </svg>
  """
  # The blank line Rails leaves for the missing `textLength` keeps its indentation.
  @david_svg String.replace(@david_svg, ~s(dy="0.35em"\n\n), ~s(dy="0.35em"\n      \n))

  setup %{conn: conn} do
    for id <- [@david, @jason, @bender], do: AvatarCache.forget(id)
    {:ok, conn: sign_in(conn, @david)}
  end

  test "the seed's image avatar: the square webp variant, as-is", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-encoding", "gzip")
      |> get("/users/#{label("avatar_tokens.jason")}/avatar")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/webp"]
    assert byte_size(conn.resp_body) == 3364
    assert get_resp_header(conn, "content-encoding") == []
    [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "max-age=1800, public, stale-while-revalidate=604800"
    assert cache =~ "no-transform"
    assert get_resp_header(conn, "content-disposition") == ["inline"]
  end

  test "initials SVG, byte for byte as Rails renders it; gzipped on request", %{conn: conn} do
    token = label("avatar_tokens.david")
    plain = get(conn, "/users/#{token}/avatar")
    assert plain.resp_body == @david_svg
    assert get_resp_header(plain, "content-type") == ["image/svg+xml; charset=utf-8"]

    gzipped =
      conn |> put_req_header("accept-encoding", "gzip, deflate") |> get("/users/#{token}/avatar")

    assert get_resp_header(gzipped, "content-encoding") == ["gzip"]
    assert :zlib.gunzip(gzipped.resp_body) == @david_svg
  end

  test "bots without an image get the default bot avatar", %{conn: conn} do
    conn = get(conn, "/users/#{Components.avatar_token(@bender)}/avatar")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
    assert conn.resp_body =~ "<svg"
  end

  test "ETag revalidation answers 304", %{conn: conn} do
    first = get(conn, "/users/#{label("avatar_tokens.jason")}/avatar")
    [etag] = get_resp_header(first, "etag")
    assert "W/" <> _ = etag

    again =
      conn
      |> put_req_header("if-none-match", etag)
      |> get("/users/#{label("avatar_tokens.jason")}/avatar")

    assert again.status == 304
    assert again.resp_body == ""
  end

  test "bad or unknown tokens are 404", %{conn: conn} do
    assert get(conn, "/users/nope/avatar").status == 404
    assert get(conn, "/users/#{label("avatar_tokens.jason")}x/avatar").status == 404
    assert get(conn, "/users/#{Components.avatar_token(1)}/avatar").status == 404
  end

  test "signed out: sent to sign in" do
    conn = get(build_conn(), "/users/#{label("avatar_tokens.jason")}/avatar")
    assert redirected_to(conn) == "/session/new"
  end

  test "uploading an avatar on the profile, then deleting it", %{conn: conn} do
    jpeg = Campfire.Storage.path("2k7n5s996jb5k5xwhx14f5oetpj4")
    before = Repo.get!(User, @david)

    upload = %Plug.Upload{path: jpeg, filename: "me.jpg", content_type: "image/jpeg"}
    conn = patch(conn, "/users/me/profile", %{"user" => %{"avatar" => upload}})
    assert redirected_to(conn) == "/users/me/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :notice) =~ "30 minutes"

    after_upload = Repo.get!(User, @david)
    assert DateTime.compare(after_upload.updated_at, before.updated_at) == :gt

    avatar = get(recycle(conn), "/users/#{Components.avatar_token(@david)}/avatar")
    assert get_resp_header(avatar, "content-type") == ["image/webp"]
    assert {:ok, image} = Vix.Vips.Image.new_from_buffer(avatar.resp_body)
    assert Vix.Vips.Image.width(image) <= 512

    profile = get(recycle(conn), "/users/me/profile") |> html_response(200)
    assert profile =~ "avatar__delete-btn"

    conn = delete(recycle(conn), "/users/#{@david}/avatar")
    assert redirected_to(conn) == "/users/me/profile"
    refute Avatars.attached?(@david)

    avatar = get(recycle(conn), "/users/#{Components.avatar_token(@david)}/avatar")
    assert avatar.resp_body == @david_svg
  end
end
