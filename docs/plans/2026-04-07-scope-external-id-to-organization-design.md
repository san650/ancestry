# Scope Person `external_id` to Organization

## Bug

When importing a CSV into a *new* organization, rows whose external IDs were
previously used by another organization fail with errors like:

```
Row 4: link failed for Adriana: :organization_mismatch
```

**Root cause:** `Ancestry.People.Person` has a globally unique constraint on
`external_id` (`priv/repo/migrations/20260317145427_add_external_id_to_persons.exs`
creates `unique_index(:persons, [:external_id])`), and `Ancestry.Import.CSV`
looks rows up via `Repo.get_by(Person, external_id: …)` with no organization
scoping. When the same source CSV is imported into a second organization, the
import finds the *other* organization's person, then tries to link her to the
target family. `Ancestry.People.add_to_family/2` rejects this with
`:organization_mismatch`, and the row is reported as a row-level failure.

External IDs from third-party sources (FamilyEcho, GEDCOM, etc.) are
tenant-scoped data, not global identifiers. Two unrelated organizations should
be free to import the same source file and end up with their own independent
person rows for the same source ID.

## Fix

Make `external_id` unique per `(organization_id, external_id)` instead of
globally, and scope every CSV import lookup to the target family's organization.

## Schema and migration

**New migration**
`priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs`:

```elixir
defmodule Ancestry.Repo.Migrations.ScopePersonExternalIdToOrganization do
  use Ecto.Migration

  def change do
    drop unique_index(:persons, [:external_id])
    create unique_index(:persons, [:organization_id, :external_id])
  end
end
```

No data transformation is needed: the old constraint was strictly stricter than
the new one, so any row that satisfied the global unique index trivially
satisfies the composite index too. Existing rows are preserved as-is.

NULL `external_id` values: PostgreSQL unique indexes treat NULLs as distinct by
default, so people created via the UI (no `external_id`) remain unaffected —
multiple per organization are still allowed.

**`lib/ancestry/people/person.ex`** — change

```elixir
|> unique_constraint(:external_id)
```

to

```elixir
|> unique_constraint([:organization_id, :external_id])
```

The Ecto changeset error is still attributed to the `:external_id` field by
default; Ecto matches against the constraint name, not the field name.

## Import lookup changes

All three `Repo.get_by(Person, external_id: …)` call sites in
`lib/ancestry/import/csv.ex` need to be scoped by `family.organization_id`. Add
a small private helper to keep the call sites readable:

```elixir
defp get_person_by_external_id(org_id, external_id) do
  Repo.get_by(Person, organization_id: org_id, external_id: external_id)
end
```

### `import_or_update_person/4` (line 170)

Replace

```elixir
case Repo.get_by(Person, external_id: attrs.external_id) do
```

with

```elixir
case get_person_by_external_id(family.organization_id, attrs.external_id) do
```

After the fix, importing into a fresh organization no longer finds the
cross-organization person and falls through to the `create_person` branch,
which creates a new organization-scoped person. The `:organization_mismatch`
path becomes unreachable from the import flow but stays in
`link_person_to_family/2` and `add_to_family/2` as defense-in-depth for other
call sites.

### `import_relationships/2` (lines 246–247)

The function currently takes only `(adapter_module, rows)` and has no access to
the family or organization. Change the signature to
`import_relationships(adapter_module, family, rows)` and update both call sites
in `import/4` and `import_for_family/3`. Then scope the source/target lookups:

```elixir
source = get_person_by_external_id(family.organization_id, source_eid)
target = get_person_by_external_id(family.organization_id, target_eid)
```

This is the only awkward bit — adding a parameter to a previously
family-agnostic function — but the alternative (passing `org_id` around as a
separate argument) is worse.

No behavior change for the same-organization happy path: re-importing into the
same organization still finds and updates the existing person.

## Tests

### Schema/changeset tests in `test/ancestry/people_test.exs`

A new describe block, `"external_id uniqueness"`:

1. Two persons in the **same organization** with the same `external_id` →
   second insert fails with the composite unique constraint error reported on
   the `:external_id` field.
2. Two persons in **different organizations** with the same `external_id` →
   both succeed.

### Cross-organization import tests in `test/ancestry/import/csv_test.exs`

A new describe block,
`"importing into a fresh organization with previously-used external_ids"`:

1. **People isolation:** Set up `org_a` and `org_b`. Import the same CSV into a
   family in `org_a`, then again into a family in `org_b`. Assert both imports
   report `people_created == N` (no `people_skipped`, no `link failed`
   errors); assert `org_a` and `org_b` each have their own `Person` rows for
   the same external IDs; assert that updating someone in `org_b` does not
   touch the corresponding row in `org_a`.

2. **Relationships isolation:** Same setup, but the CSV has parent and partner
   relationships. After importing into `org_b`, assert that the relationships
   created in `org_b` connect `org_b`'s persons (not `org_a`'s).

### Existing tests preserved

All current tests stay green:

- The same-organization `re-import` tests already exercise the
  `family.organization_id` lookup path correctly, since they re-import into the
  same family within the same organization.
- The new `linking existing people across families` tests added in the previous
  fix (`2026-04-07-csv-import-link-existing-design.md`) use two families
  inside a single shared organization, so the lookup still finds the existing
  person.

## Files changed

- `priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs` — new
- `lib/ancestry/people/person.ex` — `unique_constraint` argument
- `lib/ancestry/import/csv.ex` — three call sites + new private helper +
  `import_relationships/3` signature change + two updated callers
- `test/ancestry/people_test.exs` — new uniqueness describe block
- `test/ancestry/import/csv_test.exs` — new cross-organization describe block

## Out of scope

- Rewriting how `external_id` is generated by adapters (it stays
  `family_echo_<ID>` for the FamilyEcho adapter).
- Backfilling or deduplicating any existing data — there is nothing to
  backfill.
- Removing the `:organization_mismatch` branch from `add_to_family/2` or
  `link_person_to_family/2`. It becomes unreachable from the import flow but
  remains useful as a guard for the public `Ancestry.People` API.
- LiveView modal labels or any other UI — the previous fix
  (`2026-04-07-csv-import-link-existing-design.md`) already covers the
  user-visible state.
