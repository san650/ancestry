defmodule Ancestry.Memories.ContentParserTest do
  use ExUnit.Case, async: true

  alias Ancestry.Memories.ContentParser

  # Generates mention HTML matching actual Trix v2 innerHTML output:
  # - data-trix-attachment with &quot; entity-encoded JSON
  # - data-trix-content-type as a separate attribute
  # - Inner <span> WITHOUT data-person-id (Trix strips it)
  defp mention_figure(person_id, name) do
    ~s(<figure contenteditable="false" data-trix-attachment="{&quot;content&quot;:&quot;&lt;span data-person-id=\\&quot;#{person_id}\\&quot;&gt;@#{name}&lt;/span&gt;&quot;,&quot;contentType&quot;:&quot;application/vnd.memory-mention&quot;}" data-trix-content-type="application/vnd.memory-mention" class="attachment attachment--content"><span>@#{name}</span><figcaption class="attachment__caption"></figcaption></figure>)
  end

  defp photo_figure(photo_id, src) do
    ~s(<figure contenteditable="false" data-trix-attachment="{&quot;content&quot;:&quot;&lt;img data-photo-id=\\&quot;#{photo_id}\\&quot; src=\\&quot;#{src}\\&quot; class=\\&quot;max-w-full rounded\\&quot; /&gt;&quot;,&quot;contentType&quot;:&quot;application/vnd.memory-photo&quot;}" data-trix-content-type="application/vnd.memory-photo" class="attachment attachment--content"><img class="max-w-full rounded" src="#{src}"><figcaption class="attachment__caption"></figcaption></figure>)
  end

  describe "parse/1" do
    test "returns empty results for nil content" do
      assert ContentParser.parse(nil) == {"", [], []}
    end

    test "returns empty results for empty string" do
      assert ContentParser.parse("") == {"", [], []}
    end

    test "extracts plain text description from HTML" do
      html = "<div>Hello world, this is a memory.</div>"
      {description, _, _} = ContentParser.parse(html)
      assert description == "Hello world, this is a memory."
    end

    test "truncates description to 100 characters" do
      long_text = String.duplicate("a", 150)
      html = "<div>#{long_text}</div>"
      {description, _, _} = ContentParser.parse(html)
      assert String.length(description) == 100
    end

    test "strips figure elements from description" do
      html =
        "<div>Before image.</div>#{photo_figure(7, "/uploads/thumb.jpg")}<div>After image.</div>"

      {description, _, _} = ContentParser.parse(html)
      assert description =~ "Before image."
      assert description =~ "After image."
      refute description =~ "thumb.jpg"
    end

    test "extracts person IDs from mention attachments in actual Trix format" do
      html =
        "<div>Hello #{mention_figure(42, "John Smith")} and #{mention_figure(99, "Jane Doe")}</div>"

      {_, person_ids, _} = ContentParser.parse(html)
      assert Enum.sort(person_ids) == [42, 99]
    end

    test "extracts photo IDs from photo attachments in actual Trix format" do
      html =
        "#{photo_figure(7, "/uploads/thumb.jpg")}#{photo_figure(12, "/uploads/thumb2.jpg")}"

      {_, _, photo_ids} = ContentParser.parse(html)
      assert Enum.sort(photo_ids) == [7, 12]
    end

    test "deduplicates IDs" do
      html = "#{mention_figure(42, "John")}#{mention_figure(42, "John")}"

      {_, person_ids, _} = ContentParser.parse(html)
      assert person_ids == [42]
    end

    test "handles malformed HTML gracefully" do
      html = "<div>unclosed <strong>bold"
      {description, person_ids, photo_ids} = ContentParser.parse(html)
      assert is_binary(description)
      assert person_ids == []
      assert photo_ids == []
    end

    test "strips mention figures from description" do
      html = "<div>Remembering #{mention_figure(1, "John")} at the park</div>"
      {description, _, _} = ContentParser.parse(html)
      assert description =~ "Remembering"
      assert description =~ "at the park"
      refute description =~ "attachment"
    end
  end
end
