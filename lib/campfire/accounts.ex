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

  def get_user(id) do
    case parse_id(id) do
      nil -> nil
      id -> Replica.get(User, id)
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  @doc """
  Rails `ProfilesController#update`: name, email, password, bio. Blank email and password
  are ignored (Rails would store a blank email; has_secure_password ignores a blank password).
  """
  def update_profile(%User{} = user, params) when is_map(params) do
    changes =
      [
        name: present(params["name"]),
        email_address: present(params["email_address"]),
        bio: if(is_binary(params["bio"]), do: params["bio"]),
        password_digest: if(p = present(params["password"]), do: Bcrypt.hash_pwd_salt(p))
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    changeset = Ecto.Changeset.change(user, changes)

    case changeset.changes != %{} &&
           Repo.update(Ecto.Changeset.put_change(changeset, :updated_at, Timestamp.utc_now())) do
      false ->
        {:ok, user}

      {:ok, user} ->
        SessionCache.forget_user(user.id)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  rescue
    # The unique index on email_address.
    Ecto.ConstraintError -> {:error, :email_taken}
    Exqlite.Error -> {:error, :email_taken}
  end

  def touch_user(%User{id: id}) do
    Repo.update_all(from(u in User, where: u.id == ^id), set: [updated_at: Timestamp.utc_now()])
    SessionCache.forget_user(id)
  end

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp present(_), do: nil

  @doc """
  Users for the mentions prompt and the ping autocomplete: active users (of a room, when
  given), `name LIKE %query%`, by lower-cased name, 20 per page.
  """
  def autocompletable_users(query, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)

    base =
      case Keyword.get(opts, :room_id) do
        nil ->
          from(u in User)

        room_id ->
          from u in User,
            join: m in Campfire.Rooms.Membership,
            on: m.user_id == u.id and m.room_id == ^room_id
      end

    base
    |> where([u], u.status == :active)
    |> then(fn q ->
      if query in [nil, ""], do: q, else: where(q, [u], like(u.name, ^"%#{query}%"))
    end)
    |> order_by([u], fragment("LOWER(?)", u.name))
    |> limit(20)
    |> offset(^((page - 1) * 20))
    |> Replica.all()
  end

  ## Bans

  def banned_ip?(ip) when is_binary(ip),
    do: Replica.exists?(from b in Ban, where: b.ip_address == ^ip)

  @doc """
  Rails `User#ban`: bans every public IP the user has signed in from, deletes their sessions
  and marks them banned. (Rails then removes their messages in a job; not done here.)
  """
  def ban_user(%User{id: user_id}) do
    now = Timestamp.utc_now()

    {:ok, _} =
      Repo.transaction(fn ->
        ips =
          Repo.all(
            from s in Session,
              where: s.user_id == ^user_id and not is_nil(s.ip_address) and s.ip_address != "",
              distinct: true,
              select: s.ip_address
          )

        bans =
          for ip <- ips, public_ip?(ip) do
            %{user_id: user_id, ip_address: ip, created_at: now, updated_at: now}
          end

        if bans != [], do: Repo.insert_all(Ban, bans)

        Repo.delete_all(from s in Session, where: s.user_id == ^user_id)

        Repo.update_all(from(u in User, where: u.id == ^user_id),
          set: [status: :banned, updated_at: now]
        )
      end)

    SessionCache.forget_user(user_id)
    :ok
  end

  def unban_user(%User{id: user_id}) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.delete_all(from b in Ban, where: b.user_id == ^user_id)

        Repo.update_all(from(u in User, where: u.id == ^user_id),
          set: [status: :active, updated_at: Timestamp.utc_now()]
        )
      end)

    SessionCache.forget_user(user_id)
    :ok
  end

  # Rails `Ban` validation: no loopback, private or link-local addresses.
  defp public_ip?(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, {127, _, _, _}} -> false
      {:ok, {10, _, _, _}} -> false
      {:ok, {172, b, _, _}} when b in 16..31 -> false
      {:ok, {192, 168, _, _}} -> false
      {:ok, {169, 254, _, _}} -> false
      {:ok, {_, _, _, _}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> false
      {:ok, {a, _, _, _, _, _, _, _}} when a in 0xFC00..0xFDFF or a in 0xFE80..0xFEBF -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  ## Push subscriptions (stored only; nothing is delivered)

  def push_subscriptions(%User{id: user_id}) do
    Replica.all(from s in Subscription, where: s.user_id == ^user_id, order_by: s.id)
  end

  @doc "Rails `PushSubscriptionsController#create`: find by keys and touch, else create."
  def save_push_subscription(%User{id: user_id}, attrs, user_agent) do
    endpoint = attrs["endpoint"]
    p256dh = attrs["p256dh_key"]
    auth = attrs["auth_key"]
    now = Timestamp.utc_now()

    if valid_push_endpoint?(endpoint) do
      existing =
        Repo.one(
          from s in Subscription,
            where:
              s.user_id == ^user_id and s.endpoint == ^endpoint and s.p256dh_key == ^p256dh and
                s.auth_key == ^auth,
            limit: 1
        )

      case existing do
        %Subscription{} = s ->
          s |> Ecto.Changeset.change(updated_at: now) |> Repo.update!()

        nil ->
          Repo.insert!(%Subscription{
            user_id: user_id,
            endpoint: endpoint,
            p256dh_key: p256dh,
            auth_key: auth,
            user_agent: user_agent
          })
      end

      :ok
    else
      :error
    end
  end

  def delete_push_subscription_by_id(%User{id: user_id}, id) do
    Repo.delete_all(
      from s in Subscription, where: s.user_id == ^user_id and s.id == ^parse_id(id)
    )

    :ok
  end

  @push_hosts ~w(jmt17.google.com fcm.googleapis.com updates.push.services.mozilla.com web.push.apple.com notify.windows.com)

  # Rails validates the shape (https, port 443, a known push service) and resolves the host;
  # we never deliver, so the shape is enough.
  defp valid_push_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", port: 443, host: host} when is_binary(host) ->
        host = String.downcase(host)
        Enum.any?(@push_hosts, &(host == &1 or String.ends_with?(host, "." <> &1)))

      _ ->
        false
    end
  end

  defp valid_push_endpoint?(_), do: false

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
