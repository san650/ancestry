defmodule Ancestry.Memories.ContentParserTest do
  use ExUnit.Case, async: true

  alias Ancestry.Memories.ContentParser

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

    test "strips image figure elements from description" do
      html =
        "<div>Before image.</div><figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-photo\"}'><img data-photo-id=\"7\" src=\"/uploads/thumb.jpg\" /></figure><div>After image.</div>"

      {description, _, _} = ContentParser.parse(html)
      assert description =~ "Before image."
      assert description =~ "After image."
      refute description =~ "thumb.jpg"
    end

    test "extracts person IDs from mention attachments" do
      html =
        "<div>Hello <figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"42\">@John Smith</span></figure> and <figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"99\">@Jane Doe</span></figure></div>"

      {_, person_ids, _} = ContentParser.parse(html)
      assert Enum.sort(person_ids) == [42, 99]
    end

    test "extracts photo IDs from photo attachments" do
      html =
        "<figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-photo\"}'><img data-photo-id=\"7\" src=\"/uploads/thumb.jpg\" /></figure><figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-photo\"}'><img data-photo-id=\"12\" src=\"/uploads/thumb2.jpg\" /></figure>"

      {_, _, photo_ids} = ContentParser.parse(html)
      assert Enum.sort(photo_ids) == [7, 12]
    end

    test "deduplicates IDs" do
      html =
        "<figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"42\">@John</span></figure><figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"42\">@John</span></figure>"

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
  end
end
