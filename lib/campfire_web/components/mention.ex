defmodule CampfireWeb.Mention do
  @moduledoc """
  `users/_mention` as `Campfire.RichText.HTML` tree nodes, for the rich-text pipeline's
  `ctx.mention` and the autocomplete's editor template.

  `:editor` is the partial as Rails renders it (Lexxy keeps the `sgid`); `:presentation` is what
  survives Rails' final scrub of a message body (no `sgid`, `data-turbo-frame`, `aria-hidden`).
  """
  alias Campfire.Accounts.User
  alias Campfire.RichText.HTML
  alias Campfire.Signing
  alias CampfireWeb.Components

  def nodes(%User{} = user, :editor) do
    [
      {"span", [{"class", "mention"}, {"sgid", Signing.sgid("User", user.id)}],
       [
         {"a",
          [
            {"title", User.title(user)},
            {"class", "btn avatar"},
            {"data-turbo-frame", "_top"},
            {"href", "/users/#{user.id}"}
          ], [{"img", [{"aria-hidden", "true"} | img_attrs(user)], []}]},
         " " <> user.name
       ]}
    ]
  end

  def nodes(%User{} = user, :presentation) do
    [
      {"span", [{"class", "mention"}],
       [
         {"a",
          [{"title", User.title(user)}, {"class", "btn avatar"}, {"href", "/users/#{user.id}"}],
          [{"img", img_attrs(user), []}]},
         " " <> user.name
       ]}
    ]
  end

  @doc "The editor partial as safe HTML."
  def editor_html(%User{} = user), do: {:safe, user |> nodes(:editor) |> HTML.to_iodata()}

  defp img_attrs(user),
    do: [{"src", Components.avatar_path(user)}, {"width", "48"}, {"height", "48"}]
end
