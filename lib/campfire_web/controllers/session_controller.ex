defmodule CampfireWeb.SessionController do
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias CampfireWeb.{Plugs, RateLimiter, UserAuth}

  def new(conn, params) do
    render(conn, :new,
      email_address: params["email_address"],
      owner: Accounts.first_administrator()
    )
  end

  def create(conn, params) do
    with :ok <- rate_limit(conn),
         %Accounts.User{} = user <-
           Accounts.authenticate(params["email_address"], params["password"]) do
      UserAuth.log_in_user(conn, user)
    else
      :rate_limited -> reject(conn, :too_many_requests, params)
      nil -> reject(conn, :unauthorized, params)
    end
  end

  def delete(conn, params) do
    if endpoint = params["push_subscription_endpoint"] do
      Accounts.delete_push_subscription(conn.assigns.current_user, endpoint)
    end

    UserAuth.log_out_user(conn)
  end

  # Rails: `rate_limit to: 10, within: 3.minutes, only: :create`.
  defp rate_limit(conn) do
    limit = Application.get_env(:campfire, :login_rate_limit, 10)
    RateLimiter.hit({:sign_in, Plugs.remote_ip(conn)}, limit, 180)
  end

  defp reject(conn, status, params) do
    conn
    |> put_status(status)
    |> put_flash(:alert, "Too many requests or unauthorized.")
    |> render(:new, email_address: params["email_address"], owner: Accounts.first_administrator())
  end
end
