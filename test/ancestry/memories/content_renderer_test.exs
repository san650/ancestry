defmodule Ancestry.Memories.ContentRendererTest do
  use Ancestry.DataCase

  alias Ancestry.Memories.ContentRenderer

  # Generates mention HTML matching actual Trix v2 innerHTML output
  defp mention_figure(person_id, name) do
    ~s(<figure contenteditable="false" data-trix-attachment="{&quot;content&quot;:&quot;&lt;span data-person-id=\\&quot;#{person_id}\\&quot;&gt;@#{name}&lt;/span&gt;&quot;,&quot;contentType&quot;:&quot;application/vnd.memory-mention&quot;}" data-trix-content-type="application/vnd.memory-mention" class="attachment attachment--content"><span>@#{name}</span><figcaption class="attachment__caption"></figcaption></figure>)
  end

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

    test "transforms mention figures into linked hover cards" do
      person = insert(:person, given_name: "John", surname: "Smith")
      people_map = %{person.id => person}
      html = "<div>Hello #{mention_figure(person.id, "John Smith")}</div>"
      result = ContentRenderer.render(html, people_map, person.organization_id)

      assert result =~ ~s[href="/org/#{person.organization_id}/people/#{person.id}"]
      assert result =~ "John Smith"
      # The Trix <figure> wrapper should be replaced
      refute result =~ "data-trix-content-type"
    end

    test "leaves unknown person mentions as-is" do
      html = "<div>Hello #{mention_figure(99999, "Unknown Person")}</div>"
      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "@Unknown Person"
      refute result =~ "href"
    end

    test "transforms multiple mentions" do
      person1 = insert(:person, given_name: "John", surname: "Smith")

      person2 =
        insert(:person,
          given_name: "Jane",
          surname: "Doe",
          organization: person1.organization
        )

      people_map = %{person1.id => person1, person2.id => person2}

      html =
        "<div>#{mention_figure(person1.id, "John Smith")} and #{mention_figure(person2.id, "Jane Doe")}</div>"

      result = ContentRenderer.render(html, people_map, person1.organization_id)
      assert result =~ ~s[href="/org/#{person1.organization_id}/people/#{person1.id}"]
      assert result =~ ~s[href="/org/#{person1.organization_id}/people/#{person2.id}"]
    end

    test "preserves photo figure tags" do
      html =
        ~s(<figure contenteditable="false" data-trix-content-type="application/vnd.memory-photo" class="attachment attachment--content"><img class="max-w-full rounded" src="/uploads/photo.jpg"></figure>)

      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "<img"
      assert result =~ "photo.jpg"
    end
  end
end
