defmodule Campfire.Rooms.Presence do
  @moduledoc """
  Rails' `Membership::Connectable`: which members have the room open, kept in
  `memberships.connections` / `connected_at`. A membership is connected while
  `connected_at` is within the last 60 s (the browser refreshes every 50 s).

  Each transition is one atomic `UPDATE` on the writer (Rails reads the row first and then
  writes; the `CASE` does both). `present` doesn't touch `updated_at`, as in Rails.
  """
  alias Campfire.Repo
  alias Campfire.Schema.Timestamp

  @ttl_seconds 60

  @doc """
  Memberships with `connected_at >= cutoff()` are connected (message creation marks the
  others unread). A Rails-format text timestamp, for binding.
  """
  def cutoff(now \\ Timestamp.utc_now()), do: now |> connected_since() |> Timestamp.format()

  @doc "`cutoff/1` as a `DateTime`, for Ecto queries on `connected_at`."
  def connected_since(now), do: DateTime.add(now, -@ttl_seconds, :second)

  @doc "Opened the room (subscribe or `present` action): count it, connect, mark read."
  def present(membership_id) do
    {now, cutoff} = now_and_cutoff()

    update(
      """
      UPDATE memberships
      SET connections = CASE WHEN connected_at >= ?1 THEN connections + 1 ELSE 1 END,
          connected_at = ?2, unread_at = NULL
      WHERE id = ?3
      """,
      [cutoff, now, membership_id]
    )
  end

  @doc "Left the room (unsubscribe or `absent` action)."
  def absent(membership_id) do
    {now, cutoff} = now_and_cutoff()

    update(
      """
      UPDATE memberships
      SET connections = CASE WHEN connected_at >= ?1 THEN connections - 1 ELSE 0 END,
          connected_at = CASE WHEN connected_at >= ?1 AND connections > 1 THEN connected_at END,
          updated_at = ?2
      WHERE id = ?3
      """,
      [cutoff, now, membership_id]
    )
  end

  @doc "Still here (`refresh` action, every 50 s)."
  def refresh(membership_id) do
    {now, cutoff} = now_and_cutoff()

    update(
      """
      UPDATE memberships
      SET connections = CASE WHEN connected_at >= ?1 THEN connections ELSE 1 END,
          connected_at = ?2, updated_at = ?2
      WHERE id = ?3
      """,
      [cutoff, now, membership_id]
    )
  end

  defp now_and_cutoff do
    now = Timestamp.utc_now()
    {Timestamp.format(now), cutoff(now)}
  end

  # The number of rows updated: 0 if the membership is gone.
  defp update(sql, params), do: Repo.query!(sql, params).num_rows
end
