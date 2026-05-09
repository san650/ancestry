# Audit log: plural correlation_ids and handler metadata — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/plans/2026-05-09-audit-correlation-ids-and-handler-metadata.md` (read first — has rationale and full design context)

**Goal:** Replace `audit_log.correlation_id` (text) with `correlation_ids` (text[]); reshape `audit_log.payload` jsonb to `{arguments, metadata}`; extend `Step.audit/2` so handlers can contribute metadata; add `bch-` prefix and group batch photo uploads under one `bch-…` correlation id; render thumbnails in the audit-log UI for `AddPhotoToGallery` rows.

**Architecture:** Schema-then-callers cascade. Database first (migration), then the producer side (`Envelope`, `Bus`, `Audit.Log`, `Step`), then the writer (`AddPhotoToGalleryHandler` and the gallery-upload call site), finally the reader UI (`AuditLogLive.*`). Each task ends green so we never carry a broken tree across commits.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto + Postgres, Oban, ex_machina, PhoenixTest (E2E).

---

## Order rationale

The struct field rename (`correlation_id` → `correlation_ids`) and the `payload` shape change ripple through ~10 modules. To keep the tree compilable and tests green at each commit:

1. Add the `:batch` prefix (no consumers yet — safe alone).
2. Add the migration and run it (DB now ahead of code).
3. Update `Envelope` (the source of truth for the field).
4. Update `Bus` (immediate consumer).
5. Update `Audit.Log` schema + changeset + factory in one shot (writer; tests use the factory).
6. Add `Step.audit/2` (extension point).
7. Update audit queries (`list_correlated_entries/1`, new `_for/1`, filter clause).
8. Convert `AddPhotoToGalleryHandler` to use `Step.audit/2`.
9. Update the gallery-upload call site to pass `correlation_ids: [batch_id]`.
10. Extend Logger formatter allowlist.
11. Update audit-log UI components, then `Show`, then the index/org-index/shared filter wiring.
12. Update existing E2E tests; add new batch-grouping coverage.
13. `mix precommit`.

---

## Task 1: Register the `:batch` prefix

**Files:**
- Modify: `lib/ancestry/prefixes.ex`

- [ ] **Step 1.1: Add `batch` to `@prefixes`**

In `@prefixes` map, append `batch: "bch"` after `comment: "com"`. Compile-time guards already enforce uniqueness/length — no other changes.

- [ ] **Step 1.2: Verify**

```bash
mix compile --warnings-as-errors
```
Expected: clean compile.

- [ ] **Step 1.3: Commit**

```bash
git add lib/ancestry/prefixes.ex
git commit -m "Register :batch prefix (bch-) in Ancestry.Prefixes"
```

---

## Task 2: Migration — `correlation_ids` array + payload shape

**Files:**
- Create: `priv/repo/migrations/<timestamp>_audit_log_correlation_ids_and_payload_shape.exs`

- [ ] **Step 2.1: Generate the migration file**

```bash
mix ecto.gen.migration audit_log_correlation_ids_and_payload_shape
```

Replace its contents with:

```elixir
defmodule Ancestry.Repo.Migrations.AuditLogCorrelationIdsAndPayloadShape do
  use Ecto.Migration

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

    alter table(:audit_log) do
      modify :correlation_id, :string, null: false
    end

    alter table(:audit_log) do
      remove :correlation_ids
    end

    create index(:audit_log, [:correlation_id])
  end
end
```

- [ ] **Step 2.2: Run the migration on dev DB**

```bash
mix ecto.migrate
```
Expected: success.

- [ ] **Step 2.3: Verify the schema**

```bash
mix ecto.dump
```
Then confirm `priv/repo/structure.sql` shows `correlation_ids text[] NOT NULL DEFAULT '{}'`, no `correlation_id` column, GIN index on `correlation_ids`.

- [ ] **Step 2.4: Commit**

```bash
git add priv/repo/migrations/*_audit_log_correlation_ids_and_payload_shape.exs priv/repo/structure.sql
git commit -m "Migrate audit_log to correlation_ids array + nested payload shape"
```

> Note: from this point compiles will fail until Task 5 lands. Push through to Task 5 in one go on a working branch.

---

## Task 3: Envelope rewrite — plural field and additive `wrap/3`

**Files:**
- Modify: `lib/ancestry/bus/envelope.ex`
- Modify: `test/ancestry/bus/envelope_test.exs`

- [ ] **Step 3.1: Update existing failing assertions to match the new shape**

In `test/ancestry/bus/envelope_test.exs`:
- Line 24: `assert <<"req-", _::binary-size(36)>> = env.correlation_id` → `assert [<<"req-", _::binary-size(36)>>] = env.correlation_ids`
- Line 28-30 (`test "wrap/3 honors :correlation_id from opts"`) — rename to `"wrap/3 honors :correlation_ids from opts"`, change opt key to `:correlation_ids`, value to `["bch-fixed"]`, assertion `env.correlation_ids == ["bch-fixed"]` (when no Logger request_id is set).
- Line 36 (`assert env.correlation_id == "req-from-logger"`) → `assert env.correlation_ids == ["req-from-logger"]`.

- [ ] **Step 3.2: Add new test cases (TDD — write before implementation)**

Append to `test/ancestry/bus/envelope_test.exs`:

```elixir
test "wrap/3 prepends supplied correlation_ids before the request id" do
  Logger.metadata(request_id: "req-abc")
  env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_ids: ["bch-x"])
  assert env.correlation_ids == ["bch-x", "req-abc"]
after
  Logger.metadata(request_id: nil)
end

test "wrap/3 dedupes when supplied id matches the request id" do
  Logger.metadata(request_id: "req-abc")
  env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_ids: ["req-abc"])
  assert env.correlation_ids == ["req-abc"]
after
  Logger.metadata(request_id: nil)
end

test "wrap/3 falls back to a generated req- id when nothing is supplied" do
  env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{})
  assert [<<"req-", _::binary-size(36)>>] = env.correlation_ids
end
```

- [ ] **Step 3.3: Run the tests — they should fail**

```bash
mix test test/ancestry/bus/envelope_test.exs
```
Expected: FAIL on the new + updated assertions because the implementation still uses `correlation_id` (singular).

- [ ] **Step 3.4: Implement the new Envelope**

Replace `lib/ancestry/bus/envelope.ex` contents with:

```elixir
defmodule Ancestry.Bus.Envelope do
  @moduledoc """
  Wraps an inbound command with the dispatcher metadata required for
  authorization, audit, and tracing: caller scope, command/correlation
  ids, and issuance timestamp.
  """

  alias Ancestry.Prefixes
  require Logger

  @enforce_keys [:scope, :command_id, :correlation_ids, :issued_at, :command]
  defstruct [:scope, :command_id, :correlation_ids, :issued_at, :command]

  @type t :: %__MODULE__{
          scope: Ancestry.Identity.Scope.t(),
          command_id: String.t(),
          correlation_ids: [String.t()],
          issued_at: DateTime.t(),
          command: struct()
        }

  @spec wrap(term(), struct(), keyword()) :: t()
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

  defp current_request_id, do: Logger.metadata()[:request_id]
end
```

- [ ] **Step 3.5: Re-run envelope tests**

```bash
mix test test/ancestry/bus/envelope_test.exs
```
Expected: PASS.

- [ ] **Step 3.6: Commit**

```bash
git add lib/ancestry/bus/envelope.ex test/ancestry/bus/envelope_test.exs
git commit -m "Envelope.correlation_ids: plural list, additive merge with request id"
```

---

## Task 4: Bus dispatcher reads renamed field; Logger keys plural

**Files:**
- Modify: `lib/ancestry/bus.ex`

- [ ] **Step 4.1: Switch field reads and Logger keys**

Two call sites read `env.correlation_id` — both become plural:

In `dispatch_envelope/1` (the Logger.metadata block), change the line `correlation_id: env.correlation_id,` to `correlation_ids: env.correlation_ids,`.

In `base_metadata/1`, change `correlation_id: env.correlation_id,` to `correlation_ids: env.correlation_ids,`.

- [ ] **Step 4.2: Compile**

```bash
mix compile --warnings-as-errors
```
Expected: clean compile (provided Tasks 3 done).

- [ ] **Step 4.3: Commit**

```bash
git add lib/ancestry/bus.ex
git commit -m "Bus: read env.correlation_ids; emit plural Logger/telemetry key"
```

---

## Task 5: `Audit.Log` schema, changeset, and factory in lockstep

**Files:**
- Modify: `lib/ancestry/audit/log.ex`
- Modify: `test/support/factory.ex`
- Modify: `test/ancestry/audit/log_test.exs`

- [ ] **Step 5.1: Update the test first**

In `test/ancestry/audit/log_test.exs:37`, change:
```elixir
assert row.correlation_id == env.correlation_id
```
to:
```elixir
assert row.correlation_ids == env.correlation_ids
```

Also (search the file): assertions on `payload` likely treat it as the flat command map. Update them to read `row.payload["arguments"]` for command fields and `row.payload["metadata"]` for metadata.

Add a new test:
```elixir
test "changeset_from/2 stores handler-supplied metadata under payload.metadata" do
  env = build_envelope()  # whatever helper this file uses
  cs = Log.changeset_from(env, %{photo_id: 7})
  row = Repo.insert!(cs)

  assert row.payload["arguments"] == Serializer.serialize(env.command)
  assert row.payload["metadata"] == %{"photo_id" => 7}
end

test "changeset_from/2 rejects empty correlation_ids defensively" do
  env = build_envelope() |> Map.put(:correlation_ids, [])
  cs = Log.changeset_from(env)
  refute cs.valid?
  assert "should have at least 1 item(s)" in errors_on(cs).correlation_ids
end
```

- [ ] **Step 5.2: Run — should fail**

```bash
mix test test/ancestry/audit/log_test.exs
```
Expected: FAIL on the new assertions + several existing ones.

- [ ] **Step 5.3: Update the schema and changeset**

In `lib/ancestry/audit/log.ex`:

```elixir
schema "audit_log" do
  field :command_id, :string
  field :correlation_ids, {:array, :string}, default: []
  field :command_module, :string
  field :account_id, :integer
  field :account_name, :string
  field :account_email, :string
  field :organization_id, :integer
  field :organization_name, :string
  field :payload, :map

  timestamps(updated_at: false)
end

@required ~w(command_id correlation_ids command_module account_id account_email payload)a
@optional ~w(account_name organization_id organization_name)a

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

- [ ] **Step 5.4: Update the factory**

In `test/support/factory.ex`, in `audit_log_factory/0`:

```elixir
def audit_log_factory do
  %Ancestry.Audit.Log{
    command_id: sequence(:audit_command_id, &"cmd-#{&1}-#{Ecto.UUID.generate()}"),
    correlation_ids:
      sequence(:audit_correlation_ids, &[<<"req-">> <> "#{&1}-#{Ecto.UUID.generate()}"]),
    command_module: "Ancestry.Commands.AddCommentToPhoto",
    account_id: sequence(:audit_account_id, & &1),
    account_name: "Tester",
    account_email: sequence(:audit_email, &"audit#{&1}@example.com"),
    organization_id: nil,
    organization_name: nil,
    payload: %{
      "arguments" => %{"photo_id" => 1, "text" => "hi"},
      "metadata" => %{}
    }
  }
end
```

- [ ] **Step 5.5: Run all the affected tests**

```bash
mix test test/ancestry/audit/log_test.exs test/ancestry/audit_test.exs test/ancestry/bus/envelope_test.exs
```
Expected: log_test passes; `audit_test.exs` may still fail (Task 7 fixes), envelope test passes.

> If any test passes empty-list `correlation_ids` factory overrides, ex_machina applies them after the changeset, so they're fine — the changeset validation only runs on writes through `Log.changeset_from`.

- [ ] **Step 5.6: Commit**

```bash
git add lib/ancestry/audit/log.ex test/support/factory.ex test/ancestry/audit/log_test.exs
git commit -m "Audit.Log: correlation_ids array + nested payload shape (arguments/metadata)"
```

---

## Task 6: `Step.audit/2` for handler-contributed metadata

**Files:**
- Modify: `lib/ancestry/bus/step.ex`
- Modify: `test/ancestry/bus/step_test.exs`

- [ ] **Step 6.1: Write the failing test**

Append to `test/ancestry/bus/step_test.exs`:

```elixir
test "audit/2 writes handler-supplied metadata into payload.metadata" do
  env = build_envelope_for_step_test()  # use the file's existing helper
  multi =
    Step.new(env)
    |> Step.put(:photo, %{id: 42})
    |> Step.audit(&audit_metadata/1)
    |> Step.no_effects()

  assert {:ok, %{audit: row}} = Repo.transaction(multi)
  assert row.payload["metadata"] == %{photo_id: 42}
end

defp audit_metadata(%{photo: photo}), do: %{photo_id: photo.id}
```

(If the test file lacks an envelope helper, copy the pattern from `add_photo_to_gallery_handler_test.exs`.)

- [ ] **Step 6.2: Run — should fail**

```bash
mix test test/ancestry/bus/step_test.exs
```
Expected: FAIL with "no function clause matching" for `Step.audit/2`.

- [ ] **Step 6.3: Implement `Step.audit/2`**

Edit `lib/ancestry/bus/step.ex`:

```elixir
@doc "Append the audit step (writes one row to audit_log on commit)."
def audit(multi), do: Multi.insert(multi, :audit, &create_audit_log/1)

@doc """
Append the audit step with handler-contributed metadata. `fun` receives the
Multi changes map and returns a metadata map written to `payload.metadata`.
"""
def audit(multi, fun) when is_function(fun, 1) do
  multi
  |> Multi.run(:audit_metadata, &run_metadata_fun(&1, &2, fun))
  |> Multi.insert(:audit, &create_audit_log_with_metadata/1)
end

defp create_audit_log(%{envelope: envelope}), do: Log.changeset_from(envelope)
defp create_audit_log_with_metadata(%{envelope: env, audit_metadata: meta}),
  do: Log.changeset_from(env, meta)

defp run_metadata_fun(_repo, changes, fun), do: {:ok, fun.(changes)}
```

- [ ] **Step 6.4: Re-run**

```bash
mix test test/ancestry/bus/step_test.exs
```
Expected: PASS.

- [ ] **Step 6.5: Commit**

```bash
git add lib/ancestry/bus/step.ex test/ancestry/bus/step_test.exs
git commit -m "Step.audit/2: handler-contributed metadata via :audit_metadata step"
```

---

## Task 7: Audit context queries — singular + plural + filter

**Files:**
- Modify: `lib/ancestry/audit.ex`
- Modify: `test/ancestry/audit_test.exs`

- [ ] **Step 7.1: Update existing tests + add coverage**

In `test/ancestry/audit_test.exs`:
- Lines 77, 78, 79, 87 — change every `correlation_id: cid` factory call to `correlation_ids: [cid]` (and the `"req-other-..."` one similarly).
- Update assertions that compare `row.correlation_id` to compare `row.correlation_ids`.

Add a new test:
```elixir
test "list_correlated_entries/1 matches when the queried id is one of several" do
  cid = "bch-#{Ecto.UUID.generate()}"
  match = insert(:audit_log, correlation_ids: [cid, "req-other"])
  _miss = insert(:audit_log, correlation_ids: ["req-other"])

  assert [^match] = Audit.list_correlated_entries(cid)
end

test "list_correlated_entries_for/1 returns rows overlapping any id" do
  a = insert(:audit_log, correlation_ids: ["bch-1"])
  b = insert(:audit_log, correlation_ids: ["req-1", "bch-2"])
  _miss = insert(:audit_log, correlation_ids: ["req-2"])

  rows = Audit.list_correlated_entries_for(["bch-1", "bch-2"]) |> Enum.sort_by(& &1.id)
  assert rows == [a, b] |> Enum.sort_by(& &1.id)
end

test "list_entries/2 filters by single correlation_id" do
  cid = "bch-#{Ecto.UUID.generate()}"
  match = insert(:audit_log, correlation_ids: [cid, "req-x"])
  _miss = insert(:audit_log, correlation_ids: ["req-y"])

  assert [^match] = Audit.list_entries(%{correlation_id: cid})
end
```

- [ ] **Step 7.2: Run — fail**

```bash
mix test test/ancestry/audit_test.exs
```
Expected: FAIL.

- [ ] **Step 7.3: Implement query changes**

In `lib/ancestry/audit.ex`:

Replace `list_correlated_entries/1`:
```elixir
@doc "Every row containing `correlation_id`, oldest first."
def list_correlated_entries(correlation_id) when is_binary(correlation_id),
  do: list_correlated_entries_for([correlation_id])

@doc "Every row whose `correlation_ids` overlaps any of `ids`, oldest first."
def list_correlated_entries_for(ids) when is_list(ids) do
  Log
  |> where([l], fragment("? && ?", l.correlation_ids, ^ids))
  |> order_by([l], asc: l.inserted_at, asc: l.id)
  |> Repo.all()
end
```

Add to the `apply_filter` family:
```elixir
defp apply_filter(query, :correlation_id, %{correlation_id: id}) when is_binary(id) and id != "",
  do: where(query, [l], ^id in l.correlation_ids)
```

Add `:correlation_id` to the chain in `list_entries/2`:
```elixir
def list_entries(filters, limit \\ @default_limit) when is_map(filters) do
  Log
  |> apply_filter(:organization_id, filters)
  |> apply_filter(:account_id, filters)
  |> apply_filter(:correlation_id, filters)
  |> apply_cursor(filters)
  |> order_by([l], desc: l.inserted_at, desc: l.id)
  |> limit(^limit)
  |> Repo.all()
end
```

- [ ] **Step 7.4: Re-run**

```bash
mix test test/ancestry/audit_test.exs
```
Expected: PASS.

- [ ] **Step 7.5: Commit**

```bash
git add lib/ancestry/audit.ex test/ancestry/audit_test.exs
git commit -m "Audit: list_correlated_entries(_for) on correlation_ids array; :correlation_id filter"
```

---

## Task 8: `AddPhotoToGalleryHandler` audit metadata

**Files:**
- Modify: `lib/ancestry/handlers/add_photo_to_gallery_handler.ex`
- Modify: `test/ancestry/bus/add_photo_to_gallery_handler_test.exs`

- [ ] **Step 8.1: Update existing handler test + add coverage**

In `test/ancestry/bus/add_photo_to_gallery_handler_test.exs`:
- Find the assertion that reads the audit row's `payload`. Update it to assert on `payload["arguments"]` for the command fields.
- Add:

```elixir
test "audit row metadata records the inserted photo's id", %{scope: scope, gallery: gallery} do
  attrs = valid_photo_attrs(gallery)
  {:ok, photo} = Ancestry.Bus.dispatch(scope, Ancestry.Commands.AddPhotoToGallery.new!(attrs))

  audit = Repo.get_by!(Ancestry.Audit.Log, command_module: "Ancestry.Commands.AddPhotoToGallery")
  assert audit.payload["metadata"] == %{"photo_id" => photo.id}
end
```

(Use whatever fixture/setup pattern the file already has.)

- [ ] **Step 8.2: Run — fail**

```bash
mix test test/ancestry/bus/add_photo_to_gallery_handler_test.exs
```
Expected: FAIL on `payload["metadata"]` assertion.

- [ ] **Step 8.3: Convert the handler to `Step.audit/2`**

In `lib/ancestry/handlers/add_photo_to_gallery_handler.ex`:

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

(The other private functions stay unchanged.)

- [ ] **Step 8.4: Re-run handler tests**

```bash
mix test test/ancestry/bus/add_photo_to_gallery_handler_test.exs
```
Expected: PASS.

- [ ] **Step 8.5: Commit**

```bash
git add lib/ancestry/handlers/add_photo_to_gallery_handler.ex test/ancestry/bus/add_photo_to_gallery_handler_test.exs
git commit -m "AddPhotoToGalleryHandler: emit photo_id audit metadata via Step.audit/2"
```

---

## Task 9: Gallery batch upload — generate `bch-…` once per `process_uploads/1`

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex`
- Modify: `test/user_flows/audit_log_test.exs` (or a new file in `test/user_flows/`)

> The closure over `batch_id` inside `consume_uploaded_entries`'s callback is fine — it's a regular LiveView callback, not an `Ecto.Multi` step, so the project's "no closures over outer variables in Multi steps" rule doesn't apply.

- [ ] **Step 9.1: Add the call-site change**

In `lib/web/live/gallery_live/show.ex`, inside `process_uploads/1` (around line 322), generate the batch id **before** `consume_uploaded_entries` and pass it through every dispatch:

```elixir
defp process_uploads(socket) do
  gallery = socket.assigns.gallery
  uploads = socket.assigns.uploads.photos
  batch_id = Ancestry.Prefixes.generate(:batch)

  # ... existing invalid_results / form_results / cancel_upload setup ...

  results =
    consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
      # ... existing duplicate check + storage pre-flight ...

      case Ancestry.Bus.dispatch(
             socket.assigns.current_scope,
             Ancestry.Commands.AddPhotoToGallery.new!(attrs),
             correlation_ids: [batch_id]
           ) do
        # ... unchanged ...
      end
    end)

  # ... rest unchanged ...
end
```

- [ ] **Step 9.2: Add an E2E scenario**

Add a new test to `test/user_flows/audit_log_test.exs` (or a new file `test/user_flows/gallery_batch_upload_audit_test.exs`). Pattern: log in as admin, upload two photos to a gallery, navigate to `/admin/audit-log/<row-id>`, assert the chip strip contains a `bch-…` and the related-events panel shows the second `AddPhotoToGallery` row. Use `file_input/3` per `test/CLAUDE.md` for upload tests.

Skeleton:
```elixir
test "batch photo upload tags audit rows with one bch- correlation id", %{conn: conn} do
  # setup: admin account, gallery
  # ... use file_input/3 to upload 2 files in one form submission ...
  # query the two audit rows
  rows = Repo.all(from l in Ancestry.Audit.Log, where: l.command_module == "Ancestry.Commands.AddPhotoToGallery")
  assert length(rows) == 2
  [batch_id] = rows |> hd() |> Map.fetch!(:correlation_ids) |> Enum.filter(&String.starts_with?(&1, "bch-"))
  assert Enum.all?(rows, fn r -> batch_id in r.correlation_ids end)
end
```

- [ ] **Step 9.3: Run the test — should fail until call-site change is in place** *(it's already in place from 9.1, so this run should PASS)*

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 9.4: Commit**

```bash
git add lib/web/live/gallery_live/show.ex test/user_flows/audit_log_test.exs
git commit -m "GalleryLive.Show: tag batch uploads with shared bch- correlation id"
```

---

## Task 10: Logger formatter allowlist

**Files:**
- Modify: `config/config.exs`

- [ ] **Step 10.1: Extend `metadata:` allowlist**

In `config/config.exs:91`:
```elixir
metadata: [:request_id, :correlation_ids, :command_id]
```

- [ ] **Step 10.2: Verify locally**

```bash
iex -S mix
# in iex:
require Logger
Logger.metadata(correlation_ids: ["bch-x", "req-y"])
Logger.info("test")
```
Expected: log line includes `correlation_ids=[...]`.

- [ ] **Step 10.3: Commit**

```bash
git add config/config.exs
git commit -m "Logger: surface correlation_ids and command_id in default formatter"
```

---

## Task 11: Audit-log UI — `Components`

**Files:**
- Modify: `lib/web/live/audit_log_live/components.ex`

- [ ] **Step 11.1: Replace the row-expanded `correlation_id:` line with a chip strip**

Find the line at `components.ex:42` (`<div><strong>correlation_id:</strong> {row.correlation_id}</div>`). Replace it with a call to a new local function component:

```heex
<div><strong>correlation_ids:</strong> <.correlation_ids ids={row.correlation_ids} /></div>
```

- [ ] **Step 11.2: Update the collapsed payload preview**

`components.ex:32` — change `payload_preview(row.payload)` to `payload_preview(row.payload["arguments"])`.

`components.ex:43` — keep `Jason.encode!(row.payload, ...)` as is (it's the *raw* expanded JSON — both keys are useful).

- [ ] **Step 11.3: Add the chip-strip + metadata-cell function components**

Append to `components.ex`:

```elixir
attr :ids, :list, required: true

def correlation_ids(assigns) do
  ~H"""
  <span class="inline-flex flex-wrap gap-1">
    <.link
      :for={id <- @ids}
      navigate={~p"/admin/audit-log?correlation_id=#{id}"}
      class="font-mono text-xs px-2 py-0.5 rounded bg-zinc-100 hover:bg-zinc-200"
    >
      {id}
    </.link>
  </span>
  """
end

attr :entry, :map, required: true

def metadata_cell(%{entry: %{command_module: "Ancestry.Commands.AddPhotoToGallery"} = entry} = assigns) do
  photo_id = entry.payload["metadata"]["photo_id"]
  assigns = assign(assigns, :photo, photo_id && Ancestry.Galleries.get_photo(photo_id))
  ~H"""
  <%= cond do %>
    <% is_nil(@photo) -> %>
      <span class="text-xs text-zinc-500">{gettext("Photo deleted")}</span>
    <% @photo.status == "processed" -> %>
      <img src={Ancestry.Uploaders.Photo.url({@photo.image, @photo}, :thumbnail)}
           class="h-12 w-12 object-cover rounded" alt="" />
    <% true -> %>
      <span class="text-xs text-zinc-500">{gettext("Processing")}</span>
  <% end %>
  """
end

def metadata_cell(assigns), do: ~H""
```

> Verify `Ancestry.Galleries.get_photo/1` exists; if not, use `Repo.get(Ancestry.Galleries.Photo, photo_id)`. Verify the Waffle URL helper signature against `lib/ancestry/uploaders/photo.ex`.

- [ ] **Step 11.4: Place `<.metadata_cell entry={row} />` in the row template**

Find the `audit_table/1` row template within `components.ex` and add a metadata cell after the existing payload-preview cell, with a stable test id (`{test_id("audit-row-metadata-#{row.id}")}` on the wrapper element).

- [ ] **Step 11.5: Run audit-log tests**

```bash
mix test test/user_flows/audit_log_test.exs
```
Expected: existing chip-text assertion (line 125 — `text: a.correlation_id`) will FAIL until Task 13's E2E updates. That's fine — the new test from Task 9 should still pass.

- [ ] **Step 11.6: Commit**

```bash
git add lib/web/live/audit_log_live/components.ex
git commit -m "AuditLogLive.Components: chip strip, payload arguments preview, metadata cell"
```

---

## Task 12: Audit-log UI — `Show` (detail page)

**Files:**
- Modify: `lib/web/live/audit_log_live/show.ex`

- [ ] **Step 12.1: Switch the related-events query**

`show.ex:25` — replace:
```elixir
entry.correlation_id |> Audit.list_correlated_entries()
```
with:
```elixir
Audit.list_correlated_entries_for(entry.correlation_ids)
```

(The detail-page's neighbour set is the union over all of the entry's correlation ids.)

- [ ] **Step 12.2: Replace the `<dt>correlation_id</dt>` block**

`show.ex:61-62` — replace the existing pair:
```heex
<dt class="font-bold uppercase">correlation_id</dt>
<dd class="col-span-2">{@entry.correlation_id}</dd>
```
with:
```heex
<dt class="font-bold uppercase">correlation_ids</dt>
<dd class="col-span-2"><.correlation_ids ids={@entry.correlation_ids} /></dd>
```

(Use `Web.AuditLogLive.Components` — make sure it's imported in this file's `~H`/template context. Check the existing imports.)

- [ ] **Step 12.3: Compile + tests**

```bash
mix compile --warnings-as-errors
mix test test/user_flows/audit_log_test.exs
```
Expected: compile clean; some E2E assertions still failing (line 125 etc. — fixed in Task 14).

- [ ] **Step 12.4: Commit**

```bash
git add lib/web/live/audit_log_live/show.ex
git commit -m "AuditLogLive.Show: chip strip; related events from correlation_ids union"
```

---

## Task 13: Audit-log UI — filter wiring (`Index`, `OrgIndex`, `Shared`)

**Files:**
- Modify: `lib/web/live/audit_log_live/index.ex`
- Modify: `lib/web/live/audit_log_live/org_index.ex`
- Modify: `lib/web/live/audit_log_live/shared.ex`

- [ ] **Step 13.1: `Index` — read URL param**

In `index.ex` `parse_filters/1` (~line 110), add another line:
```elixir
|> Shared.maybe_put(:correlation_id, params["correlation_id"])
```

(`Shared.maybe_put` already drops nil; no need to wrap.)

- [ ] **Step 13.2: `OrgIndex` — read URL param + extend form-key allowlist**

In `org_index.ex` `handle_params/3` (~line 38), extend the filter chain:
```elixir
filters =
  %{organization_id: org_id}
  |> Shared.maybe_put(:account_id, Shared.parse_int(params["account_id"]))
  |> Shared.maybe_put(:correlation_id, params["correlation_id"])
```

In `org_index.ex` `handle_event("filter", ...)` (~line 58), change:
```elixir
|> Map.take(["account_id"])
```
to:
```elixir
|> Map.take(["account_id", "correlation_id"])
```

- [ ] **Step 13.3: `Shared` — match correlation filter for live updates**

In `lib/web/live/audit_log_live/shared.ex` `matches_filters?/2`, add a new branch:
```elixir
def matches_filters?(row, filters) do
  Enum.all?(filters, fn
    {:organization_id, id} -> row.organization_id == id
    {:account_id, id} -> row.account_id == id
    {:correlation_id, id} -> id in row.correlation_ids
    {:before, _} -> true
  end)
end
```

- [ ] **Step 13.4: Compile + tests**

```bash
mix compile --warnings-as-errors
mix test test/user_flows/audit_log_test.exs
```
Expected: compile clean.

- [ ] **Step 13.5: Commit**

```bash
git add lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/org_index.ex lib/web/live/audit_log_live/shared.ex
git commit -m "AuditLogLive: correlation_id filter (URL params, form, live update gate)"
```

---

## Task 14: Existing E2E assertions

**Files:**
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 14.1: Update chip-text assertions**

Line 125 — `assert_has(test_id("audit-row-expanded-#{a.id}"), text: a.correlation_id)` becomes:
```elixir
|> assert_has(test_id("audit-row-expanded-#{a.id}"), text: hd(a.correlation_ids))
```

Lines 161, 162, 175 — `correlation_id: cid` becomes `correlation_ids: [cid]`.

- [ ] **Step 14.2: Add a deleted-photo metadata test**

```elixir
test "AddPhotoToGallery audit row renders 'Photo deleted' when photo is gone", %{conn: conn} do
  scope = log_in_admin(conn)  # use the file's existing helper
  row = insert(:audit_log,
    command_module: "Ancestry.Commands.AddPhotoToGallery",
    payload: %{"arguments" => %{}, "metadata" => %{"photo_id" => 999_999}}
  )

  conn
  |> visit(~p"/admin/audit-log/#{row.id}")
  |> assert_has(test_id("audit-row-metadata-#{row.id}"), text: "Photo deleted")
end
```

- [ ] **Step 14.3: Run all E2E tests**

```bash
mix test test/user_flows/audit_log_test.exs
```
Expected: PASS.

- [ ] **Step 14.4: Commit**

```bash
git add test/user_flows/audit_log_test.exs
git commit -m "Audit-log E2E: chip-strip text, deleted-photo metadata case"
```

---

## Task 15: Final verification

- [ ] **Step 15.1: Full suite**

```bash
mix test
```
Expected: PASS.

- [ ] **Step 15.2: Precommit alias**

```bash
mix precommit
```
Expected: clean (compile warnings-as-errors, deps clean, format, tests).

- [ ] **Step 15.3: Manual smoke**

```bash
iex -S mix phx.server
```
- Log in as admin.
- Upload 3 photos to a gallery.
- Visit `/admin/audit-log` — the three rows show identical `bch-…` chips.
- Click into one — the related-events panel shows the other two.
- Click the `bch-` chip — `/admin/audit-log?correlation_id=bch-…` shows only those three rows.
- Confirm thumbnails render after worker processing completes.

- [ ] **Step 15.4: No commit needed** (everything already committed task-by-task).

---

## Files map

### Created
- `priv/repo/migrations/<timestamp>_audit_log_correlation_ids_and_payload_shape.exs`

### Modified
- `lib/ancestry/prefixes.ex`
- `lib/ancestry/bus/envelope.ex`
- `lib/ancestry/bus.ex`
- `lib/ancestry/bus/step.ex`
- `lib/ancestry/audit/log.ex`
- `lib/ancestry/audit.ex`
- `lib/ancestry/handlers/add_photo_to_gallery_handler.ex`
- `lib/web/live/gallery_live/show.ex`
- `lib/web/live/audit_log_live/components.ex`
- `lib/web/live/audit_log_live/show.ex`
- `lib/web/live/audit_log_live/index.ex`
- `lib/web/live/audit_log_live/org_index.ex`
- `lib/web/live/audit_log_live/shared.ex`
- `config/config.exs`
- `priv/repo/structure.sql` (auto-generated by `ecto.dump`)
- `test/support/factory.ex`
- `test/ancestry/bus/envelope_test.exs`
- `test/ancestry/bus/step_test.exs`
- `test/ancestry/audit/log_test.exs`
- `test/ancestry/audit_test.exs`
- `test/ancestry/bus/add_photo_to_gallery_handler_test.exs`
- `test/user_flows/audit_log_test.exs`

---

## Out-of-scope reminders (from spec)

- No metadata for handlers other than `AddPhotoToGallery`.
- No `bch-` for non-gallery batch flows (family-cover, future bulk-tag).
- No abstraction for `metadata_cell/1` dispatch beyond a `case`-style match.
- No URL snapshotting for photos.
