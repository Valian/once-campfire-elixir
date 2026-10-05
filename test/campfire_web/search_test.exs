defmodule CampfireWeb.SearchTest do
  use CampfireWeb.ConnCase

  import Ecto.Query

  alias Campfire.Searches
  alias Campfire.Searches.Search
  alias Campfire.Repo

  @david 127_326_141

  setup %{conn: conn} do
    {:ok, conn: sign_in(conn, @david)}
  end

  test "results for coffee: messages in the user's rooms, oldest first", %{conn: conn} do
    html = conn |> get("/searches?q=coffee") |> html_response(200)
    doc = LazyHTML.from_document(html)

    messages = LazyHTML.query(doc, "#search-results .message")
    assert Enum.count(messages) == 13

    stamps =
      messages |> LazyHTML.attribute("data-message-timestamp") |> Enum.map(&String.to_integer/1)

    assert stamps == Enum.sort(stamps)

    assert doc |> LazyHTML.query(".searches__query .flex-item-no-shrink") |> LazyHTML.text() ==
             "13"

    assert html =~ "<title>Search</title>"
    assert html =~ ~s(class="sidebar searches admin")
    assert doc |> LazyHTML.query("input#q") |> LazyHTML.attribute("value") == ["coffee"]
    assert LazyHTML.text(messages) =~ ~r/coffee/i

    # Every result has the room's name and the message's own permalink.
    first = Enum.at(messages, 0)
    [id] = LazyHTML.attribute(first, "data-message-id")

    assert first |> LazyHTML.query(".message__room a") |> LazyHTML.attribute("href") == [
             "/rooms/486777696/@#{id}"
           ]
  end

  test "FTS operators are searched for, not parsed (T20)", %{conn: conn} do
    for q <- ["NOT", "coffee AND", "\"", "NEAR(", "a* OR -b", "^", "💥"] do
      assert conn |> get("/searches?" <> URI.encode_query(q: q)) |> html_response(200)
    end
  end

  test "no query: recent searches, no results", %{conn: conn} do
    doc = conn |> get("/searches") |> html_response(200) |> LazyHTML.from_document()

    assert doc |> LazyHTML.query("#search-results .message") |> Enum.count() == 0
    assert doc |> LazyHTML.query(".searches__query") |> Enum.count() == 0

    recent = doc |> LazyHTML.query(".searches__recents a") |> LazyHTML.attribute("href")
    assert recent == ["/searches?q=cuckoo", "/searches?q=Borgias", "/searches?q=pizza"]
    assert doc |> LazyHTML.query("form[action='/searches/clear']") |> Enum.count() == 2
  end

  test "POST records the sanitized query and redirects", %{conn: conn} do
    conn = post(conn, "/searches", %{"q" => "pie & chips!"})
    assert redirected_to(conn) == "/searches?q=pie+++chips+"
    assert Repo.get_by(Search, user_id: @david, query: "pie   chips ")

    # Again: touched, not duplicated.
    post(recycle(conn), "/searches", %{"q" => "pie & chips!"})
    assert Repo.aggregate(from(s in Search, where: s.user_id == @david), :count) == 4
  end

  test "keeps the ten most recent searches" do
    for i <- 1..12, do: Searches.record(@david, "query #{i}")
    queries = @david |> Searches.recent() |> Enum.map(& &1.query)
    assert length(queries) == 10
    assert hd(queries) == "query 12"
    refute "pizza" in queries
  end

  test "clear deletes them all", %{conn: conn} do
    conn = delete(conn, "/searches/clear")
    assert redirected_to(conn) == "/searches"
    assert Searches.recent(@david) == []
  end

  test "match expression quotes every term" do
    assert Searches.sanitize_query("coffee-time NOT") == "coffee time NOT"
    assert Searches.match_expression("coffee time NOT") == ~s("coffee" "time" "NOT")
    assert Searches.sanitize_query("!!!") == nil
    assert Searches.sanitize_query("zażółć") == "zażółć"
  end
end
