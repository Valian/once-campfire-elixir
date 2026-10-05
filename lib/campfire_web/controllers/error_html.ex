defmodule CampfireWeb.ErrorHTML do
  @moduledoc "Error pages: Rails' static `public/{404,422,500}.html`, else the status message."

  for status <- ~w(404 422 500) do
    path = Path.expand("../../../priv/static/#{status}.html", __DIR__)
    @external_resource path

    if File.exists?(path) do
      def render(unquote(status) <> ".html", _assigns), do: {:safe, unquote(File.read!(path))}
    end
  end

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
