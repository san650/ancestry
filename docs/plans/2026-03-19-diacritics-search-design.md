# Diacritics-Insensitive Person Search

## Problem

Searching for people with diacritics in their names (e.g., "María", "José", "González") fails when the user types the unaccented version ("maria", "jose", "gonzalez") and vice versa.

## Approach

Use PostgreSQL's built-in `unaccent` extension for database queries and Unicode NFD normalization for client-side filtering.

## Design

### Database Layer

A single migration enables the `unaccent` extension:

```elixir
execute "CREATE EXTENSION IF NOT EXISTS unaccent"
```

No schema changes, no new columns, no indexes needed.

### Backend Search Queries (`Ancestry.People`)

All 4 search functions wrap both the column and the search term with `unaccent()`:

```elixir
fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like)
```

Applied to: `given_name`, `surname`, `nickname`, and the `alternate_names` unnest query. The existing search term escaping logic stays the same — just wrapped in `unaccent()`.

### Client-Side Filtering (`PersonSelectorComponent` and `KinshipLive`)

A shared helper in `Ancestry.StringUtils` strips diacritics before comparing:

```elixir
def normalize(string) do
  string
  |> String.normalize(:nfd)
  |> String.replace(~r/\p{Mn}/u, "")
  |> String.downcase()
end
```

Both components use this to normalize the search term and candidate names before `String.contains?`.

### Testing

- Unit tests in `test/ancestry/people_test.exs` for search functions with diacritics
- Unit test for `StringUtils.normalize/1`
- Update existing user flow tests if they exercise search
