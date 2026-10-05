defmodule CampfireWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders Rails' static error pages" do
    assert render_to_string(CampfireWeb.ErrorHTML, "404", "html", []) =~ "(404)"
    assert render_to_string(CampfireWeb.ErrorHTML, "500", "html", []) =~ "(500)"
    assert render_to_string(CampfireWeb.ErrorHTML, "403", "html", []) == "Forbidden"
  end
end
