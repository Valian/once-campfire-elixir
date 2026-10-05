defmodule CampfireWeb.AssetsTest do
  use ExUnit.Case, async: true

  alias CampfireWeb.Assets

  test "resolves logical paths through the Propshaft manifest" do
    assert Assets.path("add.svg") == "/assets/add-f232d8a6.svg"
    assert_raise ArgumentError, fn -> Assets.path("nope.svg") end
  end

  # Fixtures: Rails' own output for this asset build (cf-rust golden facts.json).
  test "head tags match Rails byte for byte" do
    assert Assets.stylesheet_tags() ==
             {:safe, File.read!("test/fixtures/rails_stylesheet_tags.html")}

    assert Assets.importmap_tags() ==
             {:safe, File.read!("test/fixtures/rails_importmap_tags.html")}
  end
end
