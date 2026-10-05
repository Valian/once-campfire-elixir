defmodule Campfire.Accounts do
  @moduledoc "The account, users, sign-in and sessions."
  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Accounts.{Account, Ban, Session, SessionCache, User}
  alias Campfire.Schema.Timestamp
  alias Campfire.Push.Subscription
  alias Campfire.Storage.Attachment

  @activity_refresh_seconds 3600

  ## Account (a singleton, cached for the life of the VM)

  @doc "The account, or `nil` before first run. Call `reload_account/0` after changing it."
  def account, do: cached_account() |> elem(0)

  @doc "Whether the account has a logo attached (body class `account-has-logo`)."
  def account_logo?, do: cached_account() |> elem(1)

  def reload_account do
    account = Replica.one(from a in Account, order_by: a.id, limit: 1)

    logo? =
      account != nil and
        Replica.exists?(
          from a in Attachment,
            where: a.record_type == "Account" and a.record_id == ^account.id and a.name == "logo"
        )

    if account, do: :persistent_term.put({__MODULE__, :account}, {account, logo?})
    {account, logo?}
  end

  defp cached_account do
    case :persistent_term.get({__MODULE__, :account}, nil) do
      nil -> reload_account()
      cached -> cached
    end
  end

  ## Users

  @doc "The first administrator: the sign-in page's help contact."
  def first_administrator do
    Replica.one(from u in User, where: u.role == :administrator, order_by: u.id, limit: 1)
  end

  @doc "An active user with this email and password, or `nil`. Timing doesn't leak which failed."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Replica.get_by(User, email_address: email, status: :active)

    if user && user.password_digest && Bcrypt.verify_pass(password, user.password_digest) do
      user
    else
      unless user, do: Bcrypt.no_user_verify()
      nil
    end
  end

  def authenticate(_, _), do: nil

  ## Sessions

  def start_session!(%User{} = user, user_agent: user_agent, ip_address: ip_address) do
    now = Timestamp.utc_now()

    Repo.insert!(%Session{
      user_id: user.id,
      token: secure_token(),
      user_agent: user_agent,
      ip_address: ip_address,
      last_active_at: now
    })
  end

  @doc "`{session, user}` for a session token if the user is active, else `nil`. Cached."
  def get_session_and_user(token) when is_binary(token) do
    SessionCache.fetch(token, fn ->
      query =
        from s in Session,
          join: u in assoc(s, :user),
          where: s.token == ^token and u.status == :active,
          select: {s, u}

      Replica.one(query)
    end)
  end

  @doc "Rails `Session#resume`: refreshes activity at most hourly."
  def resume_session(%Session{} = session, user, user_agent: user_agent, ip_address: ip_address) do
    now = Timestamp.utc_now()

    if DateTime.diff(now, session.last_active_at) > @activity_refresh_seconds do
      changes = [
        last_active_at: now,
        user_agent: user_agent,
        ip_address: ip_address,
        updated_at: now
      ]

      Repo.update_all(from(s in Session, where: s.id == ^session.id), set: changes)
      SessionCache.put(struct!(session, changes), user)
    end

    :ok
  end

  def delete_session(token) when is_binary(token) do
    SessionCache.delete(token)
    Repo.delete_all(from s in Session, where: s.token == ^token)
    :ok
  end

  def delete_push_subscription(%User{id: user_id}, endpoint) when is_binary(endpoint) do
    Repo.delete_all(
      from s in Subscription, where: s.user_id == ^user_id and s.endpoint == ^endpoint
    )

    :ok
  end

  ## Bans

  def banned_ip?(ip) when is_binary(ip),
    do: Replica.exists?(from b in Ban, where: b.ip_address == ^ip)

  # Rails `has_secure_token`: SecureRandom.base58(24).
  @base58 ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  defp secure_token do
    # Bytes < 232 (= 4 * 58) map uniformly onto the alphabet; the rest are discarded.
    for(<<byte <- :crypto.strong_rand_bytes(48)>>, byte < 232,
      do: Enum.at(@base58, rem(byte, 58))
    )
    |> Enum.take(24)
    |> case do
      chars when length(chars) == 24 -> List.to_string(chars)
      _ -> secure_token()
    end
  end
end
