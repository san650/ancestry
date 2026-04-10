defmodule Ancestry.Memories.ContentRendererTest do
  use Ancestry.DataCase

  alias Ancestry.Memories.ContentRenderer

  describe "render/3" do
    test "returns empty string for nil content" do
      assert ContentRenderer.render(nil, %{}, 1) == ""
    end

    test "returns empty string for empty content" do
      assert ContentRenderer.render("", %{}, 1) == ""
    end

    test "sanitizes script tags" do
      html = ~s[<div>Hello</div><script>alert('xss')</script>]
      result = ContentRenderer.render(html, %{}, 1)
      refute result =~ "<script>"
      assert result =~ "Hello"
    end

    test "sanitizes event handler attributes" do
      html = ~s[<div onclick="alert('xss')">Hello</div>]
      result = ContentRenderer.render(html, %{}, 1)
      refute result =~ "onclick"
      assert result =~ "Hello"
    end

    test "preserves allowed formatting tags" do
      html = "<div><strong>Bold</strong> and <em>italic</em></div>"
      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "<strong>Bold</strong>"
      assert result =~ "<em>italic</em>"
    end

    test "transforms mention spans into links" do
      person = insert(:person, given_name: "John", surname: "Smith")
      people_map = %{person.id => person}
      html = ~s[<span data-person-id="#{person.id}">@John Smith</span>]
      result = ContentRenderer.render(html, people_map, person.organization_id)
      assert result =~ ~s[href="/org/#{person.organization_id}/people/#{person.id}"]
      assert result =~ "John Smith"
    end

    test "leaves unknown person mentions as plain text" do
      html = ~s[<span data-person-id="99999">@Unknown</span>]
      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "@Unknown"
      refute result =~ "href"
    end

    test "preserves photo img tags" do
      html = ~s[<figure><img data-photo-id="7" src="/uploads/photo.jpg" /></figure>]
      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "<img"
      assert result =~ ~s[data-photo-id="7"]
    end
  end
end
