defmodule Ancestry.Memories.ContentParser do
  @moduledoc """
  Parses Trix-generated HTML content for memories.

  Returns a `{description, person_ids, photo_ids}` tuple where:
  - `description` is plain text (max 100 chars), with attachment figures stripped
  - `person_ids` is a deduplicated list of integer person IDs from mention attachments
  - `photo_ids` is a deduplicated list of integer photo IDs from photo attachments
  """

  @mention_content_type "application/vnd.memory-mention"
  @photo_content_type "application/vnd.memory-photo"

  @spec parse(String.t() | nil) :: {String.t(), [integer()], [integer()]}
  def parse(nil), do: {"", [], []}
  def parse(""), do: {"", [], []}

  def parse(html) when is_binary(html) do
    person_ids = extract_person_ids(html)
    photo_ids = extract_photo_ids(html)
    description = extract_description(html)
    {description, person_ids, photo_ids}
  end

  # --- Private ---

  defp extract_person_ids(html) do
    # Match mention figures: <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
    # then find <span data-person-id="N">
    figure_regex =
      ~r/<figure[^>]+data-trix-attachment='[^']*#{Regex.escape(@mention_content_type)}[^']*'[^>]*>.*?<\/figure>/s

    span_regex = ~r/data-person-id="(\d+)"/

    figure_regex
    |> Regex.scan(html)
    |> Enum.flat_map(fn [figure_html | _] ->
      Regex.scan(span_regex, figure_html)
      |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    end)
    |> Enum.uniq()
  end

  defp extract_photo_ids(html) do
    # Match photo figures: <figure data-trix-attachment='{"contentType":"application/vnd.memory-photo"}'>
    # then find <img data-photo-id="N">
    figure_regex =
      ~r/<figure[^>]+data-trix-attachment='[^']*#{Regex.escape(@photo_content_type)}[^']*'[^>]*>.*?<\/figure>/s

    img_regex = ~r/data-photo-id="(\d+)"/

    figure_regex
    |> Regex.scan(html)
    |> Enum.flat_map(fn [figure_html | _] ->
      Regex.scan(img_regex, figure_html)
      |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    end)
    |> Enum.uniq()
  end

  defp extract_description(html) do
    html
    |> strip_figure_elements()
    |> strip_html_tags()
    |> String.trim()
    |> truncate(100)
  end

  defp strip_figure_elements(html) do
    Regex.replace(~r/<figure[^>]*>.*?<\/figure>/s, html, "")
  end

  defp strip_html_tags(html) do
    # Replace block-level closing tags with a space for word boundary preservation
    html
    |> String.replace(~r/<\/(div|p|br|li|h[1-6])>/i, " ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp truncate(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length)
    else
      text
    end
  end
end
