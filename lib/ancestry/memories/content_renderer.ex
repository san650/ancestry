defmodule Ancestry.Memories.ContentRenderer do
  @moduledoc """
  Sanitizes Trix HTML and transforms mentions/photos for display.

  `render/3` returns a sanitized HTML string safe for use with `Phoenix.HTML.raw/1`.

  ## Sanitization

  Strips dangerous elements (`<script>`, `<style>`, `<iframe>`, `<object>`,
  `<embed>`, `<link>`), event-handler attributes (`on*="..."`), and
  `javascript:` URIs from `href`.

  Trix formatting tags are preserved: `<div>`, `<p>`, `<br>`, `<strong>`,
  `<em>`, `<del>`, `<blockquote>`, `<ul>`, `<ol>`, `<li>`, `<h1>`, `<a>`,
  `<pre>`, `<figure>`, `<figcaption>`, `<img>`, `<span>`.

  ## Mention transformation

  `<span data-person-id="ID">@Name</span>` is replaced with a linked hover
  card that shows the person's photo, name, and years — when the person is
  found in `people_map`.  Unknown mentions are left as plain text (the span
  is preserved but no link/card is added).
  """

  alias Ancestry.People.Person
  alias Ancestry.Uploaders.PersonPhoto

  @doc """
  Renders `html` as sanitized HTML with mention spans expanded into hover-card
  links.

  - `html` — stored Trix HTML (nil or empty returns `""`)
  - `people_map` — `%{person_id => %Person{}}` of preloaded mentioned people
  - `org_id` — organization ID used to build person profile URLs
  """
  @spec render(String.t() | nil, %{integer() => Person.t()}, integer()) :: String.t()
  def render(nil, _people_map, _org_id), do: ""
  def render("", _people_map, _org_id), do: ""

  def render(html, people_map, org_id) when is_binary(html) do
    html
    |> sanitize()
    |> transform_mentions(people_map, org_id)
  end

  # ---------------------------------------------------------------------------
  # Sanitization
  # ---------------------------------------------------------------------------

  defp sanitize(html) do
    html
    |> strip_block_tags("script")
    |> strip_block_tags("style")
    |> strip_void_tags(~w(iframe object embed link))
    |> strip_event_handlers()
    |> strip_javascript_hrefs()
  end

  # Strip <tag>...</tag> blocks including their content.
  defp strip_block_tags(html, tag) do
    re = Regex.compile!("<#{tag}[^>]*>.*?</#{tag}>", [:caseless, :dotall])
    Regex.replace(re, html, "")
  end

  # Strip self-closing or paired tags (without stripping their inner content,
  # since these are container tags that may wrap innocent text in edge cases,
  # though for safety we drop the whole element content for these dangerous
  # containers as well).
  defp strip_void_tags(html, tags) do
    Enum.reduce(tags, html, fn tag, acc ->
      # Remove both the opening/closing pair (with content) and lone self-closing tags.
      paired_re = Regex.compile!("<#{tag}[^>]*>.*?</#{tag}>", [:caseless, :dotall])
      lone_re = Regex.compile!("<#{tag}[^>]*/?>", [:caseless])

      acc
      |> then(&Regex.replace(paired_re, &1, ""))
      |> then(&Regex.replace(lone_re, &1, ""))
    end)
  end

  # Remove event-handler attributes: onclick="...", onerror='...', etc.
  # Handles both double-quoted, single-quoted, and unquoted values.
  defp strip_event_handlers(html) do
    Regex.replace(~r/\s+on\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]*)/i, html, "")
  end

  # Strip javascript: from href attributes.
  defp strip_javascript_hrefs(html) do
    Regex.replace(~r/href\s*=\s*["']?\s*javascript:[^"'\s>]*/i, html, ~s(href="#"))
  end

  # ---------------------------------------------------------------------------
  # Mention transformation
  # ---------------------------------------------------------------------------

  defp transform_mentions(html, people_map, org_id) do
    # Match entire <figure> elements with mention content type — Trix stores
    # the person ID inside the escaped JSON data-trix-attachment attribute,
    # not in the rendered <span> child.
    figure_regex =
      ~r/<figure[^>]+data-trix-content-type="application\/vnd\.memory-mention"[^>]*>.*?<\/figure>/s

    id_regex = ~r/data-person-id[^\d]*(\d+)/

    Regex.replace(figure_regex, html, fn figure_html ->
      case Regex.run(id_regex, figure_html) do
        [_, id_str] ->
          person_id = String.to_integer(id_str)

          case Map.get(people_map, person_id) do
            nil -> figure_html
            person -> render_mention(person, nil, org_id)
          end

        nil ->
          figure_html
      end
    end)
  end

  defp render_mention(%Person{} = person, _unused, org_id) do
    person_url = "/org/#{org_id}/people/#{person.id}"
    display = Person.display_name(person)
    photo_html = person_photo_html(person)
    years_html = person_years_html(person)

    """
    <span class="relative inline-block group">
      <a href="#{person_url}" class="text-ds-primary font-medium hover:underline">#{display}</a>
      <span class="absolute bottom-full left-0 mb-1 z-10 hidden group-hover:block w-48 bg-ds-surface-card rounded-ds-sharp shadow-ds-ambient p-2 text-sm pointer-events-none">
        #{photo_html}
        <span class="font-semibold text-ds-text-primary">#{display}</span>
        #{years_html}
      </span>
    </span>
    """
    |> String.trim()
  end

  defp person_photo_html(%Person{photo: nil}), do: ""

  defp person_photo_html(%Person{photo: photo} = person) when not is_nil(photo) do
    url = PersonPhoto.url({photo, person}, :thumbnail)

    ~s(<img src="#{url}" alt="" class="w-10 h-10 rounded-full object-cover mb-1" />)
  end

  defp person_years_html(%Person{birth_year: nil, death_year: nil}), do: ""

  defp person_years_html(%Person{birth_year: birth, death_year: death}) do
    text =
      case {birth, death} do
        {b, nil} -> "b. #{b}"
        {nil, d} -> "d. #{d}"
        {b, d} -> "#{b}–#{d}"
      end

    ~s(<span class="block text-ds-text-secondary text-xs">#{text}</span>)
  end
end
