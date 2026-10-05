defmodule Campfire.Searches do
  @moduledoc """
  Full-text message search (FTS5 `message_search_index`, rowid = message id) and each user's
  ten most recent searches.
  """
  import Ecto.Query

  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Messages.Message
  alias Campfire.Rooms.Membership
  alias Campfire.Searches.Search
  alias Campfire.Schema.Timestamp

  @limit 100
  @recent 10

  @doc """
  Rails `params[:q].gsub(/[^[:word:]]/, " ")`: letters, marks, digits and connector
  punctuation survive; everything else becomes a space. `nil` when nothing searchable is left.
  """
  def sanitize_query(q) when is_binary(q) do
    query = String.replace(q, ~r/[^\p{L}\p{M}\p{N}\p{Pc}]/u, " ")
    if String.trim(query) == "", do: nil, else: query
  end

  def sanitize_query(_), do: nil

  @doc """
  The FTS5 expression for a sanitized query: every term quoted, so words like `NOT`, `AND`
  or `NEAR` are searched for rather than parsed as operators (Rails 500s on them; SPEC T20).
  Terms are implicitly ANDed, as in Rails.
  """
  def match_expression(query) do
    query |> String.split() |> Enum.map_join(" ", &[?", &1, ?"])
  end

  @doc """
  The last #{@limit} matching messages in the user's rooms, oldest first, each paired with its
  indexed plain text: `[{message, plain_text}]`. Nothing is preloaded.
  """
  def search_messages(user_id, query) do
    from(m in Message,
      join: idx in "message_search_index",
      on: idx.rowid == m.id,
      where:
        m.room_id in subquery(
          from ms in Membership, where: ms.user_id == ^user_id, select: ms.room_id
        ),
      where: fragment("? MATCH ?", idx.body, ^match_expression(query)),
      order_by: [desc: m.created_at, desc: m.id],
      limit: @limit,
      select: {m, idx.body}
    )
    |> Replica.all()
    |> Enum.reverse()
  end

  @doc "The user's recent searches, newest first."
  def recent(user_id) do
    Replica.all(from s in Search, where: s.user_id == ^user_id, order_by: [desc: s.updated_at])
  end

  @doc """
  Rails `searches.record(query)`: find or create, touch, and keep only the newest
  #{@recent} once a new one is created.
  """
  def record(user_id, query) when is_binary(query) do
    now = Timestamp.utc_now()

    Repo.transaction(fn ->
      case Repo.one(
             from s in Search, where: s.user_id == ^user_id and s.query == ^query, limit: 1
           ) do
        %Search{} = search ->
          search |> Ecto.Changeset.change(updated_at: now) |> Repo.update!()

        nil ->
          Repo.insert!(%Search{user_id: user_id, query: query, created_at: now, updated_at: now})

          keep =
            from s in Search,
              where: s.user_id == ^user_id,
              order_by: [desc: s.updated_at, desc: s.id],
              limit: @recent,
              select: s.id

          Repo.delete_all(
            from s in Search, where: s.user_id == ^user_id and s.id not in subquery(keep)
          )
      end
    end)

    :ok
  end

  def clear(user_id) do
    Repo.delete_all(from s in Search, where: s.user_id == ^user_id)
    :ok
  end
end
