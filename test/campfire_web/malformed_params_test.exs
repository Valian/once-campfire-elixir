defmodule CampfireWeb.MalformedParamsTest do
  use CampfireWeb.ConnCase

  setup %{conn: conn}, do: {:ok, conn: sign_in(conn, label("users.david"))}

  test "nested or non-numeric ids and params answer without a 500", %{conn: conn} do
    room = label("rooms.watercooler")

    assert get(conn, "/rooms/#{room}/messages?before[x]=1").status == 404
    assert get(recycle(conn), "/rooms/#{room}/refresh?since[]=1").status == 200
    assert get(recycle(conn), "/rooms/abc").status == 302
    assert get(recycle(conn), "/messages/abc/boosts").status in [302, 404]

    assert delete(recycle(conn), "/users/me/push_subscriptions/abc").status < 500

    conn =
      post(recycle(conn), "/users/me/push_subscriptions", %{
        "push_subscription" => %{"endpoint" => "https://fcm.googleapis.com/x"}
      })

    assert conn.status < 500
  end
end
