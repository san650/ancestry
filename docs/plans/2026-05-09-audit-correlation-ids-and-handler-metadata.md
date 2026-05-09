# Audit log: plural correlation ids and handler-contributed metadata

**Date:** 2026-05-09
**Branch:** `audit-log`
**Status:** Design

## Summary

Two related upgrades to the audit log:

1. **`correlation_id` becomes `correlation_ids` (a list).** A single audit row may belong to several correlation groups at once — e.g. an HTTP request *and* a batch upload. This unblocks grouping batch-dispatched commands (10 photos uploaded in one go) under a single `bch-…` id while still letting them appear under their originating `req-…`.
2. **Handlers can contribute extra audit metadata.** The `payload` column gains a structured shape `{ "arguments": <command>, "metadata": <handler-supplied map> }`. `AddPhotoToGallery` is converted now: it records `{photo_id: ...}` so the audit-log UI can render the photo's thumbnail. Other handlers stay metadata-less for now and migrate opportunistically.

The motivating user flow: when a user batch-uploads 10 photos in `Web.GalleryLive.Show`, the resulting 10 audit rows all share one `bch-<uuid>` correlation id, the audit-log detail page links them as related events, and each row renders a thumbnail of the uploaded photo.

## Background

### Current state

`Ancestry.Bus.dispatch/3` already accepts `opts` and forwards them to `Envelope.wrap/3` (`lib/ancestry/bus.ex:11`). `Envelope.wrap/3` already supports `opts[:correlation_id]` with a fallback chain:

1. explicit `opts[:correlation_id]`
2. `Logger.metadata()[:request_id]`
3. `Prefixes.generate(:request)` → a fresh `req-…` id

Every successful dispatch writes one row to `audit_log` via `Step.audit/0`. The row carries a single `correlation_id` (text, indexed) and a `payload` (jsonb) that is the serialized command struct (binary fields replaced by sentinels via `Ancestry.Audit.Serializer`).

`Ancestry.Audit.list_correlated_entries/1` queries `where l.correlation_id == ^id` to pull all rows from one group.

The audit-log UI (`Web.AuditLogLive.Index`, `Show`, `OrgIndex`, plus the shared `Web.AuditLogLive.Components`) renders rows with the correlation id displayed as a single value and a detail page that lists "events sharing this correlation_id".

### What's missing

- Batch dispatches (e.g. uploading 10 photos in `Web.GalleryLive.Show.process_uploads/1`) generate 10 independent audit rows whose `correlation_id` is whatever ambient request id Logger metadata happens to hold — usually nothing meaningful from inside a LiveView channel event. There's no way to group "these 10 commands were one user action".
- The audit-log UI has no way to render command-specific extras. For an `AddPhotoToGallery` row, the most useful thing to show is the photo itself, but there's no slot for that data.

## Goals

- A single audit row may belong to multiple correlation groups; querying by any one id finds it.
- Adding a new prefixed id type (today: `bch-` for batch upload) is one entry in `Ancestry.Prefixes` plus a call-site change.
- Handlers may contribute extra metadata into the audit row without touching the audit subsystem; the DSL exposes a single new arity (`Step.audit/2`).
- The audit-log UI renders, for `AddPhotoToGallery`, a thumbnail of the uploaded photo (or a placeholder when the photo is still processing or has been deleted).
- The batch-upload flow in `Web.GalleryLive.Show.process_uploads/1` tags every dispatched `AddPhotoToGallery` with the same `bch-<uuid>`.

## Non-goals

- No new audit columns. The existing `payload` column is reshaped, not replaced.
- No backfill of historical metadata. Existing rows migrate to `payload = {"arguments": <old_payload>, "metadata": {}}` and stay that way.
- No application of `bch-…` to other flows yet (family-cover bulk uploads, future bulk-tagging). The Envelope/Step changes are generic; extending later is one call-site change each.
- No new render branches for handlers other than `AddPhotoToGallery` — those will land in follow-up work.
- No change to telemetry consumers' contracts beyond the rename (`correlation_id` → `correlation_ids`).
- No introduction of an `Ecto.Type` for the prefixed-id format. Strings, as today.

## Architecture

### Data model

`audit_log.correlation_id` (text) → `audit_log.correlation_ids` (text[]), indexed with GIN so `WHERE ^id = ANY(correlation_ids)` is fast.

The existing `payload` column **stays** — it changes shape, not name. Every row's `payload` now conforms to:

```json
{
  "arguments": { ...serialized command... },
  "metadata":  { ...handler-supplied map (often {})... }
}
```

`Ancestry.Audit.Log` schema:

```elixir
schema "audit_log" do
  field :command_id,        :string
  field :correlation_ids,   {:array, :string}, default: []
  field :command_module,    :string
  field :account_id,        :integer
  field :account_name,      :string
  field :account_email,     :string
  field :organization_id,   :integer
  field :organization_name, :string
  field :payload,           :map     # %{"arguments" => map, "metadata" => map}

  timestamps(updated_at: false)
end
```

`@required` updates: `correlation_id` → `correlation_ids`. Note that `Ecto.Changeset.validate_required/2` treats `[]` as present (only `nil` is missing), so the changeset adds an explicit `validate_length(:correlation_ids, min: 1)` as a defensive backstop — `Envelope.wrap/3` already guarantees at least one id (see Envelope semantics below), and this is belt-and-braces.

### Migration

```elixir
# priv/repo/migrations/<timestamp>_audit_log_correlation_ids_and_payload_shape.exs
def up do
  alter table(:audit_log) do
    add :correlation_ids, {:array, :string}, null: false, default: []
  end

  execute "UPDATE audit_log SET correlation_ids = ARRAY[correlation_id]"

  drop index(:audit_log, [:correlation_id])

  alter table(:audit_log) do
    remove :correlation_id
  end

  create index(:audit_log, [:correlation_ids], using: :gin)

  execute """
  UPDATE audit_log
  SET payload = jsonb_build_object('arguments', payload, 'metadata', '{}'::jsonb)
  """
end

def down do
  execute "UPDATE audit_log SET payload = payload->'arguments'"

  drop index(:audit_log, [:correlation_ids])

  alter table(:audit_log) do
    add :correlation_id, :string
  end

  execute "UPDATE audit_log SET correlation_id = correlation_ids[1]"

  # Split the final alter into two blocks: tightening NOT NULL must precede
  # removal of `correlation_ids` to avoid mixing modify+remove in one statement.
  alter table(:audit_log) do
    modify :correlation_id, :string, null: false
  end

  alter table(:audit_log) do
    remove :correlation_ids
  end

  create index(:audit_log, [:correlation_id])
end
```

### Envelope

`%Envelope{correlation_id: String.t()}` → `%Envelope{correlation_ids: [String.t()]}`.

`wrap/3` builds the list **additively**: caller-supplied ids first (more specific), the ambient request id last. If neither is present, generate one fresh `req-…` so every envelope has at least one id (preserves today's "every audit row has a correlation" invariant).

```elixir
def wrap(scope, command, opts \\ []) do
  ids =
    (List.wrap(opts[:correlation_ids]) ++ [current_request_id()])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> ensure_at_least_one()

  %__MODULE__{
    scope: scope,
    command: command,
    command_id: Prefixes.generate(:command),
    correlation_ids: ids,
    issued_at: DateTime.utc_now()
  }
end

defp ensure_at_least_one([]), do: [Prefixes.generate(:request)]
defp ensure_at_least_one(list), do: list
```

The `:correlation_id` (singular) opt is **removed** — there are very few call sites and the new shape is what we want everywhere. Tests that previously asserted on `correlation_id` now assert on the list.

### Bus / Logger / telemetry

Both `Bus.dispatch_envelope/1` (currently `lib/ancestry/bus.ex:17`) and `Bus.base_metadata/1` (currently `lib/ancestry/bus.ex:104`) read the renamed envelope field. Both switch from `env.correlation_id` to `env.correlation_ids`. Logger and telemetry both switch the singular key to plural:

```elixir
Logger.metadata(
  command_id: env.command_id,
  correlation_ids: env.correlation_ids,
  command_module: inspect(module)
)
```

Logger handles list-valued metadata natively, but the formatter allowlist needs to know about the new key. `config/config.exs:91` configures `metadata: [:request_id]` for the default formatter — extend it to `metadata: [:request_id, :correlation_ids, :command_id]` so the new metadata appears in dev/prod logs. (`:command_id` was already populated but never surfaced; piggy-backing on this change.)

### Step DSL

```elixir
# zero-arg: unchanged
Step.audit()

# one-arg: handler computes metadata from prior Multi changes
Step.audit(&audit_metadata/1)
```

Implementation in `Ancestry.Bus.Step`:

```elixir
def audit(multi), do: Multi.insert(multi, :audit, &create_audit_log/1)

def audit(multi, fun) when is_function(fun, 1) do
  multi
  |> Multi.run(:audit_metadata, &run_metadata_fun(&1, &2, fun))
  |> Multi.insert(:audit, &create_audit_log_with_metadata/1)
end

defp run_metadata_fun(_repo, changes, fun), do: {:ok, fun.(changes)}
defp create_audit_log(%{envelope: env}),
  do: Log.changeset_from(env)
defp create_audit_log_with_metadata(%{envelope: env, audit_metadata: meta}),
  do: Log.changeset_from(env, meta)
```

`:audit_metadata` joins `:envelope`, `:audit`, `:effects` as a reserved Multi step name. The 1-arg form keeps the project rule "no inline anonymous functions inside Multi steps" — the only `fun.(changes)` call lives behind a named function inside `Step` itself, never in handler code.

`Log.changeset_from/2`:

```elixir
def changeset_from(env, metadata \\ %{}) do
  %__MODULE__{}
  |> cast(attrs_from(env, metadata), @required ++ @optional)
  |> validate_required(@required)
  |> validate_length(:correlation_ids, min: 1)
end

defp attrs_from(env, metadata) do
  %{
    command_id: env.command_id,
    correlation_ids: env.correlation_ids,
    command_module: inspect(env.command.__struct__),
    account_id: env.scope.account.id,
    account_name: env.scope.account.name,
    account_email: env.scope.account.email,
    organization_id: org_id(env.scope),
    organization_name: org_name(env.scope),
    payload: %{
      "arguments" => Serializer.serialize(env.command),
      "metadata" => metadata
    }
  }
end
```

### Audit query

`Ancestry.Audit.list_correlated_entries/1` keeps its singular-argument shape — callers want "rows that include *this* id" — but the where-clause changes:

```elixir
def list_correlated_entries(correlation_id) when is_binary(correlation_id) do
  Log
  |> where([l], ^correlation_id in l.correlation_ids)
  |> order_by([l], asc: l.inserted_at, asc: l.id)
  |> Repo.all()
end
```

Ecto compiles `^id in l.correlation_ids` to `^id = ANY(correlation_ids)`, which uses the GIN index.

### Prefixes registry

```elixir
@prefixes %{
  command:      "cmd",
  request:      "req",
  account:      "acc",
  organization: "org",
  photo:        "pho",
  gallery:      "gal",
  family:       "fam",
  person:       "per",
  comment:      "com",
  batch:        "bch"   # new
}
```

### Call site: `Web.GalleryLive.Show.process_uploads/1`

```elixir
defp process_uploads(socket) do
  # ...existing setup...
  batch_id = Ancestry.Prefixes.generate(:batch)

  results =
    consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
      # ...existing duplicate check + storage pre-flight...

      case Ancestry.Bus.dispatch(
             socket.assigns.current_scope,
             Ancestry.Commands.AddPhotoToGallery.new!(attrs),
             correlation_ids: [batch_id]
           ) do
        # ...same result handling...
      end
    end)
  # ...
end
```

Even when the user uploads a single file the dispatch carries a `bch-…` — a "batch of one" is still a batch. Cheaper than branching on cardinality.

### Handler: `AddPhotoToGallery`

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.insert(:inserted_photo, &add_photo_to_gallery/1)
  |> Step.run(:photo, &preload_photo_gallery/2)
  |> Step.enqueue(:transform_job, &transform_and_store_photo/1)
  |> Step.audit(&audit_metadata/1)
  |> Step.no_effects()
end

defp audit_metadata(%{photo: photo}), do: %{photo_id: photo.id}
```

The handler stores a **reference**, not a snapshot URL. Three reasons:

1. The URL isn't known at audit-write time — `photo.image` stays `nil` until the `TransformAndStorePhoto` worker finishes.
2. URLs depend on storage config (asset host, cache busters, signing). A stored URL would go stale.
3. View-time lookup naturally handles deletion (placeholder instead of broken `<img>`).

### Audit-log UI

`Web.AuditLogLive.Components`, `Web.AuditLogLive.Show`, and `Web.AuditLogLive.Shared` all touch the renamed field or the new payload shape. Specific call sites:

- `lib/web/live/audit_log_live/components.ex:32` — `payload_preview(row.payload)` — change to `payload_preview(row.payload["arguments"])` so the collapsed-row preview shows command arguments, not the wrapper keys.
- `lib/web/live/audit_log_live/components.ex:42` — `correlation_id: {row.correlation_id}` — replaced by a chip strip from the new `correlation_ids/1` function component.
- `lib/web/live/audit_log_live/components.ex:43` — `Jason.encode!(row.payload, pretty: true)` — keep the full payload pretty-printed (it's the expanded "raw" view; showing both `arguments` and `metadata` here is desirable).
- `lib/web/live/audit_log_live/show.ex:25` — `entry.correlation_id |> Audit.list_correlated_entries()` — switch to `Audit.list_correlated_entries_for(entry.correlation_ids)` (new plural function — see "Detail page: related events" below).
- `lib/web/live/audit_log_live/show.ex:61-62` — the `<dt>correlation_id</dt><dd>{@entry.correlation_id}</dd>` block — replaced by the chip strip.
- `lib/web/live/audit_log_live/show.ex:65` — `Jason.encode!(@entry.payload, pretty: true)` — keep as-is (raw view).

The three new UI building blocks:

1. **Argument display.** Wherever the old code rendered `entry.payload` as the *command summary* (i.e. the collapsed preview at `components.ex:32`), it now renders `entry.payload["arguments"]`. The expanded raw views keep the full envelope-shaped payload.
2. **Correlation-ids strip.** A new `correlation_ids/1` function component renders each id as a small monospace chip. Each chip is a link to the index filtered to that single id (`/admin/audit-log?correlation_id=<id>` — see Filter URL state below). Same component used in the row-expanded view, the detail page header, and the related-events row prefix.
3. **Metadata cell.** A new `metadata_cell/1` function component branches on `entry.command_module`:

   ```elixir
   defp metadata_cell(%{entry: %{command_module: "Ancestry.Commands.AddPhotoToGallery"} = entry} = assigns) do
     ~H"<.add_photo_to_gallery_metadata photo_id={@entry.payload["metadata"]["photo_id"]} />"
   end
   defp metadata_cell(assigns), do: ~H""  # other commands: nothing for now
   ```

   `add_photo_to_gallery_metadata/1` calls `Ancestry.Galleries.get_photo(photo_id)` and renders one of:
   - photo present, status `"processed"` → small `<img>` thumbnail (`Photo.url({photo.image, photo}, :thumbnail)`)
   - photo present, status `"pending"` or `"failed"` → small status badge ("Processing…" / "Processing failed")
   - photo missing (deleted) → "Photo deleted" placeholder

### Detail page: related events

`Web.AuditLogLive.Show` shows a single "Related events" panel containing every other row that shares **any** of this entry's `correlation_ids`, sorted by `inserted_at` ascending. Each related row renders the same chip strip so the reader sees which id(s) connected it. One panel, one scroll — the chips do the disambiguation.

Two related functions live side-by-side, used at distinct call sites:

- `Audit.list_correlated_entries/1` — singular `correlation_id` argument, returns rows containing that one id. Used by chip deep-links (each chip is one id).
- `Audit.list_correlated_entries_for/1` — list of correlation ids, returns rows whose `correlation_ids` overlap any of the given ids (Postgres `&&`). Used by the detail-page related-events panel where the entry itself carries multiple ids.

The singular form is rewritten in terms of the plural form internally so we maintain one canonical implementation.

Implementation of the plural form:

```elixir
def list_correlated_entries_for(ids) when is_list(ids) do
  Log
  |> where([l], fragment("? && ?", l.correlation_ids, ^ids))   # array overlap
  |> order_by([l], asc: l.inserted_at, asc: l.id)
  |> Repo.all()
end
```

Postgres `&&` (array overlap) uses the GIN index.

### Filter URL state

The `Web.AuditLogLive.Index` and `OrgIndex` filter form gains a `correlation_id` filter (singular — users filter by one id at a time). Reuses the existing list query path with one new `apply_filter` clause in `Ancestry.Audit`:

```elixir
defp apply_filter(query, :correlation_id, %{correlation_id: id}) when is_binary(id) and id != "",
  do: where(query, [l], ^id in l.correlation_ids)
```

The filter form input is hidden by default but a deep-link from a chip populates it.

Three integration points need updating so the new filter actually flows end-to-end:

- `lib/web/live/audit_log_live/index.ex` `parse_filters/1` (~line 110) — add a `Shared.maybe_put(:correlation_id, params["correlation_id"])` call. The `handle_event("filter", ...)` clause in `index.ex` already passes the form params through unfiltered, so no guard change there.
- `lib/web/live/audit_log_live/org_index.ex` — two changes:
  - `handle_params/3` (~line 38) — extend the filter-building chain with `Shared.maybe_put(:correlation_id, params["correlation_id"])` so URL-supplied ids actually reach the query.
  - `handle_event("filter", ...)` (~line 58) — extend `Map.take(["account_id"])` to `Map.take(["account_id", "correlation_id"])` so submitted form values reach the URL. Without this, deep-links from chips on the org-scoped page silently drop the filter.
- `lib/web/live/audit_log_live/shared.ex` `matches_filters?/2` (~line 14) — add a `{:correlation_id, id} -> id in row.correlation_ids` branch. Without it, the live PubSub `{:audit_logged, row}` handler will insert rows into the stream regardless of the active correlation filter.

## Tests

### Unit

- `test/ancestry/bus/envelope_test.exs`
  - `wrap/3` returns `correlation_ids: [request_id]` when no opts and request_id is in Logger metadata.
  - `wrap/3` returns `correlation_ids: [explicit, request_id]` when both supplied; explicit comes first.
  - `wrap/3` dedupes when `opts[:correlation_ids]` already contains the request id.
  - `wrap/3` falls back to a fresh `req-…` when neither opts nor Logger metadata has anything.
- `test/ancestry/bus/step_test.exs` (new or extended)
  - `Step.audit/2` runs the metadata fn against prior Multi changes and the resulting row's `payload["metadata"]` matches the returned map.
  - `Step.audit/1` (zero-arg) writes `payload["metadata"] == %{}`.
- `test/ancestry/audit/log_test.exs`
  - `changeset_from/2` writes `payload` as `%{"arguments" => ..., "metadata" => meta}`.
  - `changeset_from/1` writes `metadata` as `%{}`.
- `test/ancestry/audit_test.exs`
  - `list_correlated_entries/1` matches when the queried id is one of several in `correlation_ids`.
  - `list_correlated_entries_for/1` returns the union when given multiple ids.

### Factory

`test/support/factory.ex`:

```elixir
audit_log_factory: %Audit.Log{
  correlation_ids: [sequence(:audit_correlation_id, &"req-#{&1}-#{Ecto.UUID.generate()}")],
  payload: %{"arguments" => %{}, "metadata" => %{}},
  ...
}
```

### E2E (`test/user_flows/`)

- **Existing `audit_log_test.exs`** — update assertions that reference `correlation_id` (singular) to read from `correlation_ids` (one chip per id).
- **New scenario in the gallery batch-upload flow** — upload N=2 photos, then visit `/admin/audit-log/<photo-1-row-id>` and assert:
  - the row's chip strip contains a `bch-…` id
  - the related-events panel includes the second `AddPhotoToGallery` row
  - the metadata cell renders an `<img>` (after worker completion in test mode) or a "Processing" badge
- **New unit-ish coverage** in the audit-log LiveView: an `AddPhotoToGallery` row whose `metadata.photo_id` no longer exists renders the "Photo deleted" placeholder.

## Out of scope (intentionally)

- **Other handlers' metadata.** `AddCommentToPhoto`, `TagPersonInPhoto`, etc. keep `metadata = %{}`. Each gets its own metadata function and UI render branch in follow-up work, opportunistically.
- **Other batch flows.** `FamilyLive.Show` family-cover uploads and any future bulk operations stay request-scoped only. Adding `bch-…` to them is a one-line change later.
- **A render-strategy abstraction for `metadata_cell/1`.** Until a third command grows a metadata renderer, the `case`-style dispatch in the function component is fine. Premature to introduce a behaviour or registry.
- **Snapshotting photo URLs into the audit row.** See "Why store a reference, not a URL" above.
- **Filter UI for `correlation_id` beyond a single field.** Multi-select / chip-stack filtering is a future polish.

## Files changed

### Modified
- `lib/ancestry/prefixes.ex` — add `:batch` → `"bch"`.
- `lib/ancestry/bus/envelope.ex` — field rename, `wrap/3` rewrite.
- `lib/ancestry/bus.ex` — `dispatch_envelope/1` (line 17) and `base_metadata/1` (line 104) read `env.correlation_ids` instead of `env.correlation_id`; Logger / telemetry metadata key renamed accordingly.
- `lib/ancestry/bus/step.ex` — add `audit/2`, reserved `:audit_metadata` step.
- `lib/ancestry/audit.ex` — `list_correlated_entries/1` query change; new `list_correlated_entries_for/1`; new `apply_filter` clause.
- `lib/ancestry/audit/log.ex` — schema field, `changeset_from/1,2`, `attrs_from/2`.
- `lib/ancestry/handlers/add_photo_to_gallery_handler.ex` — switch to `Step.audit/2` with `audit_metadata/1`.
- `lib/web/live/gallery_live/show.ex` — generate `bch-…` once per `process_uploads/1`, pass `correlation_ids:` to each dispatch.
- `lib/web/live/audit_log_live/show.ex` — chip strip (replaces `correlation_id` `<dd>`), metadata cell, related-events panel uses `list_correlated_entries_for/1`.
- `lib/web/live/audit_log_live/components.ex` — `correlation_ids/1` and `metadata_cell/1` function components; collapsed preview reads `payload["arguments"]`.
- `lib/web/live/audit_log_live/index.ex` — `parse_filters/1` reads `correlation_id`; form field added.
- `lib/web/live/audit_log_live/org_index.ex` — same `parse_filters/1` change *and* extend the `Map.take(["account_id"])` allowlist to include `"correlation_id"`.
- `lib/web/live/audit_log_live/shared.ex` — new `:correlation_id` branch in `matches_filters?/2`.
- `config/config.exs` — extend Logger formatter `metadata:` allowlist to include `:correlation_ids` (and `:command_id`).
- `test/support/factory.ex` — `correlation_ids: [...]`, `payload: %{"arguments" => %{}, "metadata" => %{}}`.
- `test/ancestry/bus/envelope_test.exs` — assertion updates and new merge/dedup cases.
- `test/ancestry/audit/log_test.exs` — assertion updates.
- `test/ancestry/audit_test.exs` — assertion updates and new coverage.
- `test/user_flows/audit_log_test.exs` — chip-strip assertions; deleted-photo metadata case.

### Added
- `priv/repo/migrations/<timestamp>_audit_log_correlation_ids_and_payload_shape.exs`
- `test/ancestry/bus/step_test.exs` (if not already present — extend if it is)
- A new E2E scenario in `test/user_flows/gallery_batch_upload_test.exs` (or extension of the existing gallery flow file).

## Open questions

None — design decisions:
- Auto-include request id in `correlation_ids`: **yes**.
- Related-events panel: **single union panel** with chip strip per row.
- Storage shape: **single `payload` jsonb with `{arguments, metadata}` keys**.
