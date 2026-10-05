defmodule CampfireWeb.PushSubscriptionController do
  @moduledoc """
  `/users/me/push_subscriptions`: stores the browser's push subscription (so the bell's
  `notifications:ready` fires and the involvement frame loads). Nothing is ever pushed.
  """
  use CampfireWeb, :controller

  alias Campfire.Accounts

  def index(conn, _params) do
    render(conn, :index, subscriptions: Accounts.push_subscriptions(conn.assigns.current_user))
  end

  def create(conn, %{"push_subscription" => attrs}) when is_map(attrs) do
    user_agent = conn |> get_req_header("user-agent") |> List.first()

    case Accounts.save_push_subscription(conn.assigns.current_user, attrs, user_agent) do
      :ok -> send_resp(conn, 200, "")
      :error -> send_resp(conn, 422, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, 400, "")

  def delete(conn, %{"id" => id}) do
    :ok = Accounts.delete_push_subscription_by_id(conn.assigns.current_user, id)
    redirect(conn, to: ~p"/users/me/push_subscriptions")
  end
end
