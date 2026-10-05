defmodule Campfire.Avatars do
  @moduledoc """
  User avatars: the Active Storage attachment `User`/`avatar` and its `square` variant
  (`resize_to_limit: [512, 512], format: :webp`), through `Campfire.Storage`, so either app
  finds the other's files (SPEC §2.4).
  """
  import Ecto.Query

  alias Campfire.Accounts.{SessionCache, User}
  alias Campfire.Repo
  alias Campfire.Repo.Replica
  alias Campfire.Schema.Timestamp
  alias Campfire.Storage
  alias Campfire.Storage.{Attachment, Blob}

  @square [format: {:sym, "webp"}, resize_to_limit: [512, 512]]

  @doc "The avatar blob, if one is attached."
  def avatar_blob(user_id) do
    Replica.one(
      from a in Attachment,
        join: b in assoc(a, :blob),
        where: a.record_type == "User" and a.record_id == ^user_id and a.name == "avatar",
        order_by: [desc: a.id],
        limit: 1,
        select: b
    )
  end

  def attached?(user_id), do: avatar_blob(user_id) != nil

  @doc """
  The path of the avatar's square webp variant, generating it if missing. `nil` when the
  user has no avatar or it isn't an image libvips can process (Rails `avatar_variant`).
  """
  def square_path(user_id) do
    with %Blob{} = blob <- avatar_blob(user_id),
         true <- Storage.variable?(blob),
         {:ok, %Blob{} = square} <- Storage.ensure_variant(blob, @square) do
      Storage.path(square)
    else
      _ -> nil
    end
  end

  @doc """
  Attaches an uploaded image as the user's avatar (replacing any previous one), generates
  the square variant, and bumps the user's `updated_at` (so `?v=` changes).
  """
  def attach(%User{id: user_id}, %Plug.Upload{} = upload) do
    blob = Storage.store_upload(upload)

    {:ok, old_keys} =
      Repo.transaction(fn ->
        old_keys = Storage.purge_attachments!("User", user_id, "avatar")
        blob |> Storage.insert_blob!() |> Storage.attach!("User", user_id, "avatar")
        touch_user!(user_id)
        old_keys
      end)

    Storage.delete_files(old_keys)
    _ = square_path(user_id)
    :ok
  end

  @doc "Removes the user's avatar (Rails `avatar.destroy`, which touches the user)."
  def remove(%User{id: user_id}) do
    {:ok, keys} =
      Repo.transaction(fn ->
        keys = Storage.purge_attachments!("User", user_id, "avatar")
        if keys != [], do: touch_user!(user_id)
        keys
      end)

    Storage.delete_files(keys)
    :ok
  end

  defp touch_user!(user_id) do
    Repo.update_all(from(u in User, where: u.id == ^user_id),
      set: [updated_at: Timestamp.utc_now()]
    )

    SessionCache.forget_user(user_id)
  end
end
