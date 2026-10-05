defmodule CampfireWeb.AvatarCache do
  @moduledoc """
  Avatar responses, ready to send, in ETS keyed by avatar token: a hit costs one lookup (no
  signature check, no query, no file read). Rails gets the same effect from Thruster's HTTP
  cache.

  Entries are dropped by `forget/1` whenever the user changes (profile, avatar), which is
  the only thing that can change an avatar. The cache is bounded by the number of users:
  only verified tokens are stored.
  """
  use GenServer

  import Ecto.Query

  alias Campfire.Accounts.User
  alias Campfire.Avatars
  alias Campfire.Repo.Replica
  alias Campfire.Signing

  @table __MODULE__

  @type entry :: %{
          etag: String.t(),
          content_type: String.t(),
          body: binary(),
          gzip: binary() | nil
        }

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The avatar for a signed avatar token; `:error` if it doesn't verify or the user's gone."
  @spec fetch(String.t()) :: {:ok, entry} | :error
  def fetch(token) do
    case :ets.lookup(@table, token) do
      [{_token, _user_id, entry}] ->
        {:ok, entry}

      [] ->
        with {:ok, id} <- Signing.verify_signed_id(token, "user/avatar"),
             %User{} = user <- Replica.one(from u in User, where: u.id == ^id) do
          entry = build(user)
          :ets.insert(@table, {token, id, entry})
          {:ok, entry}
        else
          _ -> :error
        end
    end
  end

  def forget(user_id) do
    :ets.match_delete(@table, {:_, user_id, :_})
    :ok
  end

  defp build(%User{} = user) do
    etag = ~s(W/"#{user.id}-#{Calendar.strftime(user.updated_at, "%Y%m%d%H%M%S%f")}")

    cond do
      path = Avatars.square_path(user.id) ->
        %{etag: etag, content_type: "image/webp", body: File.read!(path), gzip: nil}

      User.bot?(user) ->
        svg(etag, "image/svg+xml", default_bot_svg())

      true ->
        svg(etag, "image/svg+xml; charset=utf-8", initials_svg(user))
    end
  end

  defp svg(etag, type, body),
    do: %{etag: etag, content_type: type, body: body, gzip: :zlib.gzip(body)}

  @colors ~w(#AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E #D07B53
             #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F #3B3633 #67695E)
          |> List.to_tuple()

  @doc "`users/avatars/show.svg.erb`: initials on a colour picked by CRC32 of the user id."
  def initials_svg(%User{id: id} = user) do
    initials = User.initials(user)
    color = elem(@colors, rem(:erlang.crc32(Integer.to_string(id)), tuple_size(@colors)))

    text_length =
      if String.length(initials) >= 3,
        do: ~s(textLength="85%" lengthAdjust="spacingAndGlyphs"),
        else: ""

    """
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
      viewBox="0 0 512 512" class="avatar" aria-hidden="true">
      <defs>
        <clipPath id="porthole">
          <circle cx="50%" cy="50%" r="50%" />
        </clipPath>
      </defs>

      <g>
        <rect width="100%" height="100%" rx="50" fill="#{color}" />

        <text x="50%" y="50%" fill="#FFFFFF"
          text-anchor="middle" dy="0.35em"
          #{text_length}
          font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
          font-size="230"
          font-weight="800"
          letter-spacing="-5">
          #{Phoenix.HTML.html_escape(initials) |> Phoenix.HTML.safe_to_string()}
        </text>
      </g>
    </svg>
    """
  end

  defp default_bot_svg do
    "/assets/" <> digested = CampfireWeb.Assets.path("default-bot-avatar.svg")
    File.read!(Application.app_dir(:campfire, ["priv", "static", "assets", digested]))
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
