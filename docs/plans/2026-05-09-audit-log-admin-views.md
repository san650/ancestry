# Audit log admin views

**Date:** 2026-05-09
**Branch:** `audit-log`
**Status:** Design

## Summary

Expose the existing `audit_log` table through a read-only UI for super-admins (`:admin` role). Two index pages (top-level and organization-scoped) plus a detail page for individual entries with `correlation_id` grouping. No new schema, no migrations — only LiveView, a query-only context module, a PubSub broadcast in the Bus dispatcher, and a permission rule.

## Background

`Ancestry.Bus.dispatch/2` already writes one denormalized row per successful command dispatch via `Step.audit/0`. Schema (`Ancestry.Audit.Log`):

- `command_id`, `correlation_id`, `command_module`
- `account_id`, `account_name`, `account_email`
- `organization_id`, `organization_name`
- `payload` (jsonb, with redacted/binary fields replaced by sentinels via `Ancestry.Audit.Serializer`)
- `inserted_at`

The migration `20260507155719_create_audit_log.exs` already creates the indexes this feature needs:

- `unique_index(:audit_log, [:command_id])`
- `index(:audit_log, [:correlation_id])`
- `index(:audit_log, [:account_id, :inserted_at])`
- `index(:audit_log, [:organization_id, :inserted_at])`
- `index(:audit_log, [:command_module, :inserted_at])`

No additional indexes required.

Roles today are `:admin` (super-admin), `:editor`, `:viewer`. Only `:admin` can view the audit log; no new role is introduced for this feature.

## Goals

- Super-admins can browse all audit-log entries at `/admin/audit-log`.
- Super-admins can browse audit-log entries scoped to one organization at `/org/:org_id/audit-log`.
- Super-admins can drill into a single entry to see its full payload and any other entries that share its `correlation_id`.
- Filter by organization (top-level only) and by account.
- Infinite scroll over a LiveView stream.
- New audit entries appear in real time via PubSub without reload.

## Non-goals

- No "org admin" role. Editors and viewers see no audit UI.
- No humanized event sentences. Rows show the raw command module name and a JSON payload preview. Adding new commands does not require any UI work.
- No date-range or command-type filters in v1. The two structured filters (org + account) plus real-time updates are enough.
- No CSV export, no retention policy UI, no archive.
- No free-text search across payload.
- No pagination URL deep-links to a specific position. Filter state is in the URL, but scroll position is not.
- No introduction of `flop`, `paginator`, or `scrivener`. Vanilla Ecto cursor pagination.

## Architecture

### Routes & LiveViews

| Route | LiveView | `live_session` | Resource shown |
|---|---|---|---|
| `/admin/audit-log` | `Web.AuditLogLive.Index` | `:admin` | All audit rows |
| `/admin/audit-log/:id` | `Web.AuditLogLive.Show` | `:admin` | One row + correlated rows |
| `/org/:org_id/audit-log` | `Web.AuditLogLive.OrgIndex` | `:organization` | Audit rows where `organization_id == :org_id` |

`Index` and `OrgIndex` are separate LiveViews because they live in different `live_session`s (different `on_mount` hooks: the org-scoped one needs `Web.EnsureOrganization`). They share rendering through a function-component module `Web.AuditLogLive.Components` containing:

- `audit_table/1` — the stream-rendered table with click-to-expand rows.
- `filter_bar/1` — the filter form (the `organization` filter is hidden in the org-scoped variant).
- `viewport_sentinel/1` — the `phx-viewport-bottom` element that triggers `load_more`.

`Show` is its own thing.

### Authorization

`Ancestry.Permissions`:

```elixir
def can(%Scope{account: %Account{role: :admin}}) do
  permit()
  |> ...existing rules...
  |> all(Ancestry.Audit.Log)
end
```

All three LiveViews use `Permit.Phoenix.LiveView` with `resource_module: Ancestry.Audit.Log`. The `all/1` Permit rule covers every action (`:index`, `:show`, and any future read action) for super-admins. No record-level authorization is needed: super-admin sees everything, and the org-scoped `OrgIndex` enforces its scope through the **query** (`organization_id == :org_id`) rather than through Permit.

Unauthorized accounts redirect to `/org` with the standard flash, matching the pattern in `Web.AccountManagementLive.Index`.

### Data layer

A new query-only context module `Ancestry.Audit` sits next to the existing `Ancestry.Audit.Log` and `Ancestry.Audit.Serializer`:

```elixir
defmodule Ancestry.Audit do
  @moduledoc "Read-only queries over the audit_log table."

  @default_limit 50

  # Filters: %{organization_id: integer | nil, account_id: integer | nil,
  #           before: {NaiveDateTime.t(), integer()} | nil}
  # Returns rows ordered by (inserted_at DESC, id DESC), at most `limit`.
  def list_entries(filters, limit \\ @default_limit), do: ...

  def get_entry!(id), do: ...

  # All entries with the same correlation_id, oldest first.
  def list_correlated_entries(correlation_id), do: ...
end
```

Cursor pagination uses Postgres tuple compare:

```sql
WHERE (inserted_at, id) < ($before_inserted_at, $before_id)
ORDER BY inserted_at DESC, id DESC
LIMIT $limit
```

This is stable under concurrent inserts (a row appearing while paginating cannot duplicate or skip pages, since the ordering tuple is strictly monotonic). Filters compose as additional optional `WHERE` clauses on `organization_id` and `account_id`. The query is small enough that a hand-written Ecto query is shorter than configuring `Flop.Schema`.

`Ancestry.Audit` exposes **only queries**. It never inserts, updates, or deletes — those continue to flow through `Ancestry.Bus`.

### Real-time updates

Broadcast happens **inside `Ancestry.Bus`**, not in handlers. After the transaction commits successfully, the dispatcher takes the row from `multi_changes[:audit]` and publishes it on two topics:

- `"audit_log"` — every audit row.
- `"audit_log:org:#{organization_id}"` — only when `organization_id` is non-nil.

Message shape: `{:audit_logged, %Ancestry.Audit.Log{}}`.

**Mechanism.** The dispatcher already fires a list of post-commit effects returned by handlers' `Step.effects/1` (e.g. `{:broadcast, topic, msg}`, `{:waffle_delete, photo}`). The audit broadcasts are emitted by the **dispatcher itself** — not by handlers, and not by appending to the handler's effects list. After the transaction commits and before (or after — order is irrelevant) the handler's effects fire, the dispatcher reads `multi_changes[:audit]` and calls `Phoenix.PubSub.broadcast/3` directly on the two topics. This is a hard-coded dispatcher step, not a returned-effect tuple, because the audit row is generated by the dispatcher's own `Step.audit/0` — not by the handler — and broadcasting it is infrastructure-level concern, not domain-level. Handlers stay focused on their domain effects.

This is a non-transactional side effect. It runs after `Repo.transaction/1` returns `{:ok, _}` — never inside the Multi. Failed dispatches (validation, authorization, conflict, exception) write nothing and broadcast nothing.

LiveView subscriptions:

- `Index` subscribes to `"audit_log"`.
- `OrgIndex` subscribes only to `"audit_log:org:#{org_id}"` for its organization. It does **not** subscribe to the global topic — broadcasting per-org keeps fan-out tight.
- `Show` does not subscribe (its data is static once loaded).

When a `{:audit_logged, row}` arrives, the LiveView checks the row against the active filters in `socket.assigns`. Matching rows are inserted at the front of the stream via `stream_insert(socket, :entries, row, at: 0)`. Non-matching rows are discarded.

### UI

**Toolbar.** Both index pages use the project's brutalist toolbar pattern (matching `Web.AccountManagementLive.Index`). Title: `gettext("Audit log")`.

**Filter bar.** Two `<.input type="select">` controls on the top-level page; one (account) on the org-scoped page. Options for "Organization" come from `Ancestry.Organizations.list_organizations/0`. Options for "Account" come from a dedicated `Ancestry.Audit.list_audit_accounts/1` query that returns `DISTINCT account_id, account_email` from `audit_log`, so the dropdown only shows accounts that have actually appeared in the log.

The "Account" dropdown is **scoped to the page's context**:
- On `/admin/audit-log`, `list_audit_accounts(filters)` returns every account that has appeared in the global log. If an organization filter is also active, the account dropdown re-narrows to accounts that have appeared in *that* org. (Both filters update together via the same `phx-change` handler.)
- On `/org/:org_id/audit-log`, `list_audit_accounts(%{organization_id: org_id})` returns only accounts that have appeared in that org's log — never accounts from other orgs.

Changing a filter pushes a `phx-change` event that:
1. Patches the URL with the new filter params (`?organization_id=...&account_id=...`).
2. Resets the stream (`stream(socket, :entries, [], reset: true)`).
3. Re-queries from the head with the new filters.

Filter state is parsed from URL params on `handle_params/3` so reload + link-share works.

**Table columns.** Timestamp (relative time with absolute timestamp tooltip), account email, organization name, command (last segment of `command_module`, e.g. `AddCommentToPhoto`), payload preview (truncated JSON, ~120 chars). Each row has a `phx-click="toggle"` handler that flips `expanded?` for that row.

**Inline expand.** When expanded, the row reveals: `command_id`, `correlation_id`, full pretty-printed payload. The row also includes a small "open" link/icon → `/admin/audit-log/:id`.

The inline expand and the detail page both show the full payload — that overlap is intentional. The inline expand exists for fast in-context inspection while browsing the table. The detail page exists for two things the inline expand cannot do: (1) display the **correlated rows** that share a `correlation_id`, and (2) provide a **shareable URL** for an individual entry (link from a Slack thread, a bug report, etc.). They are not redundant; they cover different access patterns.

**Infinite scroll.** A sentinel element at the bottom of the stream:

```heex
<div
  :if={@has_more?}
  phx-viewport-bottom={JS.push("load_more")}
  id="audit-log-sentinel"
/>
```

`load_more` fetches the next page using the bottom-most row's `(inserted_at, id)` as the cursor and `stream_insert`s appended rows. When the server returns fewer than `@limit` rows, `has_more?` is set to `false` and the sentinel disappears.

**Detail page (`Show`).** Full record at the top: timestamp, account, organization, full `command_module`, `command_id`, `correlation_id`, pretty-printed JSON payload. Below: a "Related events" section listing every other row with the same `correlation_id`, ordered chronologically. If none exist, the section reads `gettext("No related events")`.

**Navigation.** New entries in `<.nav_drawer>`:

- A top-level "Audit log" link to `/admin/audit-log`, alongside the existing "Accounts" admin link, visible only when `can?(@current_scope, :index, Ancestry.Audit.Log)` is true.
- An org-level "Audit log" link to `/org/:org_id/audit-log`, alongside other org entries, visible under the same `can?` rule when an organization is loaded into the scope.

Visibility is **always** checked through `Ancestry.Authorization.can?/3` — never a direct `account.role == :admin` comparison.

### i18n

All visible strings go through `gettext/1` and get Spanish translations in `priv/gettext/es-UY/LC_MESSAGES/`. Strings: "Audit log", "Organization", "Account", "Load more", "Related events", "No related events", "All organizations", "All accounts", "Command", "Payload", expand/collapse labels.

Command module names are not translated — they are engineering labels and rendered verbatim.

## Data flow

```
LiveView mount
  ├─ parse filter params from URL
  ├─ subscribe to PubSub topic
  └─ list_entries(filters, limit) → stream

User changes filter
  ├─ patch URL with new params
  ├─ reset stream
  └─ list_entries(new_filters, limit) → stream

User scrolls to bottom (phx-viewport-bottom)
  └─ list_entries(filters ++ {before: cursor}, limit) → stream_insert (append)

User clicks row
  └─ toggle :expanded? for that row id

User clicks "open"
  └─ navigate to /admin/audit-log/:id (Show)

Bus.dispatch succeeds
  ├─ commit txn (audit row written by Step.audit)
  ├─ broadcast {:audit_logged, row} on "audit_log"
  └─ broadcast {:audit_logged, row} on "audit_log:org:#{org_id}" (if any)

LiveView receives {:audit_logged, row}
  └─ if row matches current filters → stream_insert at: 0
     else → discard
```

## Error handling

- **Unauthorized access.** Permit denies; LiveView's `handle_unauthorized/2` redirects to `/org` with `gettext("You don't have permission to access this page")`.
- **Detail page with bad id.** `get_entry!/1` raises `Ecto.NoResultsError`; Phoenix returns 404. No special handling.
- **Empty result set.** Render an empty state in the table body: `gettext("No audit entries match the current filters.")`. The infinite-scroll sentinel is not rendered when the stream is empty.
- **PubSub broadcast failure.** Silently swallowed by `Phoenix.PubSub.broadcast/3`. The audit row is already committed; only the live view goes briefly stale until reload. This is acceptable.
- **Stale filter dropdowns.** The "Account" dropdown reflects accounts that have appeared in the log at query time. New accounts that appear via real-time inserts will not retroactively populate the dropdown until the page reloads. Acceptable for v1.

## Testing

E2E tests in `test/user_flows/audit_log_test.exs` per `test/user_flows/CLAUDE.md`. Each scenario uses real preloaded data and exercises rendered templates. Use cases:

- **Top-level index renders all rows.** Audit rows seeded across two organizations; super-admin visits `/admin/audit-log`; both orgs' rows visible, newest first.
- **Filter by organization narrows results.** Same setup; pick org A; only org A's rows visible; URL contains `?organization_id=...`.
- **Filter by account narrows results.** Two accounts have dispatched commands; pick one; only their rows visible.
- **Combined filters compose.** Both filters active; only the intersection is shown.
- **Infinite scroll loads older rows.** Seed > `@default_limit` rows; trigger `phx-viewport-bottom`; older rows append; sentinel removed when exhausted.
- **Real-time prepend.** Subscribe through the LiveView; `Ancestry.Bus.dispatch/2` a new command from another scope; new row appears at the top without reload; row matching active filters appears, non-matching is discarded.
- **Inline expand.** Click a row; expanded panel shows `command_id`, `correlation_id`, full payload; click again collapses.
- **Detail page renders correlated rows.** Insert two rows with the same `correlation_id`; visit `/admin/audit-log/:id` for one; the other is listed under "Related events"; also exercise the "No related events" copy when the row is alone.
- **Org-scoped page is scoped.** Visit `/org/:org_a_id/audit-log` while audit rows exist for both orgs; only org A's rows appear; the organization filter dropdown is absent.
- **Authorization denies non-admins.** `:editor`, `:viewer`, and unauthenticated requests on all three routes redirect with the unauthorized flash.
- **Nav drawer visibility.** Render the drawer as super-admin (link visible) and as editor (link absent), top-level and inside an organization.

Unit tests:

- `Ancestry.Audit.list_entries/2` — filter combinations; cursor correctness (passing the bottom row's `(inserted_at, id)` returns strictly older rows with no duplicates); ordering invariant.
- `Ancestry.Audit.list_correlated_entries/1` — chronological order; consistent inclusion/exclusion of the focal row.
- `Ancestry.Audit.list_audit_accounts/1` — DISTINCT correctness; org scoping.
- `Ancestry.Bus` dispatcher — successful dispatch broadcasts on `"audit_log"` and `"audit_log:org:#{id}"` (when org present); failed dispatch (validation, unauthorized, exception) broadcasts nothing and writes no row.

Permit tests — extend the existing permissions test file: `:admin` can `:index` and `:show` `Ancestry.Audit.Log`; `:editor`, `:viewer`, anonymous cannot.

`mix precommit` is the merge gate.

## Files

### New

- `lib/ancestry/audit.ex` — query-only context (`list_entries/2`, `get_entry!/1`, `list_correlated_entries/1`, `list_audit_accounts/1`).
- `lib/web/live/audit_log_live/index.ex` — top-level LiveView.
- `lib/web/live/audit_log_live/org_index.ex` — org-scoped LiveView.
- `lib/web/live/audit_log_live/show.ex` — detail LiveView.
- `lib/web/live/audit_log_live/components.ex` — shared function components (`audit_table/1`, `filter_bar/1`, `viewport_sentinel/1`, `expanded_row_panel/1`).
- `test/user_flows/audit_log_test.exs` — E2E coverage.
- `test/ancestry/audit_test.exs` — unit tests for the query module.

### Modified

- `lib/ancestry/permissions.ex` — add `all(Ancestry.Audit.Log)` to the `:admin` rule.
- `lib/ancestry/bus.ex` — broadcast `{:audit_logged, row}` on `"audit_log"` and `"audit_log:org:#{id}"` after successful commit.
- `lib/web/router.ex` — three new `live` routes.
- `lib/web/components/nav_drawer.ex` — two new conditional links (top-level admin entry, org-level entry).
- `priv/gettext/default.pot` and `priv/gettext/es-UY/LC_MESSAGES/default.po` — new translation entries (run `mix gettext.extract --merge`).
- `test/ancestry/bus_test.exs` (or similar) — broadcast assertions.
- `test/ancestry/permissions_test.exs` — `Ancestry.Audit.Log` access matrix.

### Migrations

None.

## Open questions

None blocking. Future enhancements (out of scope for v1):

- Date-range filter.
- Command-type filter (the `(command_module, inserted_at)` index already exists).
- Free-text search across payload.
- CSV export.
- Humanized per-command renderers.
- Retention / archival.
