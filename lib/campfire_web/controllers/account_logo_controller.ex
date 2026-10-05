defmodule CampfireWeb.AccountLogoController do
  @moduledoc """
  `GET /account/logo[?size=small]` (no sign-in): the account logo as a 512 (or 192) px PNG
  variant, or the stock app icon when none is attached (Rails `Accounts::LogosController`).
  """
  use CampfireWeb, :controller

  import Ecto.Query

  alias Campfire.Accounts
  alias Campfire.Repo.Replica
  alias Campfire.Storage
  alias Campfire.Storage.{Attachment, Blob}

  @cache_control "max-age=300, public, stale-while-revalidate=604800"

  def show(conn, params) do
    small? = params["size"] == "small"

    conn
    |> put_resp_content_type("image/png", nil)
    |> put_resp_header("cache-control", @cache_control)
    |> send_file(200, logo_path(small?) || stock_icon(small?))
  end

  defp logo_path(small?) do
    size = if small?, do: 192, else: 512

    with %{id: account_id} <- Accounts.account(),
         true <- Accounts.account_logo?(),
         %Blob{} = blob <- logo_blob(account_id),
         {:ok, %Blob{} = variant} <-
           Storage.ensure_variant(blob, format: {:sym, "png"}, resize_to_limit: [size, size]) do
      Storage.path(variant)
    else
      _ -> nil
    end
  end

  defp logo_blob(account_id) do
    Replica.one(
      from a in Attachment,
        join: b in assoc(a, :blob),
        where: a.record_type == "Account" and a.record_id == ^account_id and a.name == "logo",
        limit: 1,
        select: b
    )
  end

  defp stock_icon(small?) do
    "/assets/" <> digested =
      CampfireWeb.Assets.path(if small?, do: "logos/app-icon-192.png", else: "logos/app-icon.png")

    Application.app_dir(:campfire, ["priv", "static", "assets", digested])
  end
end
