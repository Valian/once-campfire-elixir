defmodule CampfireWeb.Assets do
  @moduledoc """
  The Rails app's precompiled assets (`priv/static/assets`, see `bin/extract-assets`).

  Everything is resolved at compile time from Propshaft's `.manifest.json`: `path/1` is one
  function clause per asset, and the `<head>` tags Rails renders with `stylesheet_link_tag :all`
  and `javascript_importmap_tags` are prebuilt iodata.
  """

  @manifest_path "priv/static/assets/.manifest.json"
  @external_resource @manifest_path

  @manifest @manifest_path
            |> File.read!()
            |> Jason.decode!()
            |> Map.new(fn {logical, %{"digested_path" => digested}} ->
              {logical, "/assets/" <> digested}
            end)

  @doc ~S"""
  The URL of a logical asset path: `path("add.svg")` is `"/assets/add-f232d8a6.svg"`.
  Raises for unknown assets, like Rails.
  """
  for {logical, url} <- @manifest do
    def path(unquote(logical)), do: unquote(url)
  end

  def path(logical), do: raise(ArgumentError, "unknown asset #{inspect(logical)}")

  # config/importmap.rb, in order: explicit pins, then `pin_all_from` directories (each
  # directory's files sorted by path; `dir/index.js` is pinned as `dir`).
  @pins [
    {"application", "application.js"},
    {"@hotwired/stimulus", "stimulus.min.js"},
    {"@hotwired/stimulus-loading", "stimulus-loading.js"},
    {"@hotwired/turbo-rails", "turbo.js"},
    {"@rails/actioncable", "actioncable.esm.js"},
    {"@rails/request.js", "@rails--request.js"},
    {"lexxy", "lexxy.js"},
    {"highlight.js", "highlight.js/core.js"}
  ]
  @pin_all_from ~w(initializers lib channels controllers helpers models languages)

  @importmap @pins ++
               for(
                 dir <- @pin_all_from,
                 logical <- @manifest |> Map.keys() |> Enum.sort(),
                 String.starts_with?(logical, dir <> "/") and String.ends_with?(logical, ".js"),
                 do:
                   {logical |> String.trim_trailing(".js") |> String.replace_suffix("/index", ""),
                    logical}
               )

  @stylesheet_tags @manifest
                   |> Map.keys()
                   |> Enum.filter(&String.ends_with?(&1, ".css"))
                   |> Enum.sort()
                   |> Enum.map_join("\n", fn logical ->
                     ~s(<link rel="stylesheet" href="#{@manifest[logical]}" data-turbo-track="reload" />)
                   end)

  @importmap_tags [
                    ~s(<script type="importmap" data-turbo-track="reload">{\n  "imports": {\n),
                    Enum.map_join(@importmap, ",\n", fn {name, logical} ->
                      ~s(    "#{name}": "#{@manifest[logical]}")
                    end),
                    ~s(\n  }\n}</script>\n),
                    Enum.map_join(@importmap, "\n", fn {_, logical} ->
                      ~s(<link rel="modulepreload" href="#{@manifest[logical]}">)
                    end),
                    ~s(\n<script type="module">import "application"</script>)
                  ]
                  |> IO.iodata_to_binary()

  @doc "Rails' `stylesheet_link_tag :all, \"data-turbo-track\": \"reload\"`: every CSS file, sorted."
  def stylesheet_tags, do: {:safe, @stylesheet_tags}

  @doc "Rails' `javascript_importmap_tags`: the import map, modulepreloads and the entry point."
  def importmap_tags, do: {:safe, @importmap_tags}
end
