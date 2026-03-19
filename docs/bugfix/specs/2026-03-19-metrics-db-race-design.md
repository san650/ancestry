# Fix: Metrics DB connection race in tests

## Bug

`FamilyLive.Show.mount/3` calls `Metrics.compute/1` synchronously — 4 sequential DB queries that block mount. When a test navigates away before the connected mount finishes those queries, the test process (DB connection owner) exits, orphaning the connection and producing noisy `owner exited` errors in test output.

## Root cause

`Metrics.compute/1` runs 4 queries (count_people, count_photos, find_longest_line, find_oldest_person) synchronously in mount. The connected mount process holds the DB connection from the test's sandbox, but the test process can exit before all queries complete.

## Fix

Use `assign_async/3` to load metrics asynchronously. Mount returns immediately; metrics load in a supervised task that is cleaned up if the LiveView process dies.

### `FamilyLive.Show.mount/3`

Replace synchronous metrics with `assign_async`:

```elixir
# Before:
metrics = Metrics.compute(family_id)
|> assign(:metrics, metrics)

# After:
|> assign_async(:metrics, fn -> {:ok, %{metrics: Metrics.compute(family_id)}} end)
```

### `SidePanelComponent`

`@metrics` becomes an `AsyncResult`. Guard the metrics section on `@metrics.ok?`:

```elixir
<%= if @metrics.ok? && @metrics.result.people_count > 0 do %>
  <%!-- existing metrics markup, replacing @metrics.X with @metrics.result.X --%>
<% end %>
```

No loading skeleton needed — galleries and people list render immediately, metrics appear a moment later.

### Template (`show.html.heex`)

No change — `metrics={@metrics}` passes the AsyncResult through.
