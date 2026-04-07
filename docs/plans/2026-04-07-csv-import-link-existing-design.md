# CSV Import: Link Existing People to Family

## Bug

When importing a CSV into a family, if a person already exists in the system (matched by `external_id`), the import updates the person's fields but **does not link them to the current family**. The expected behavior is that duplicate people should not be re-created, but they **must** be linked to the family the import is targeting.

**Root cause:** `Ancestry.Import.CSV.import_or_update_person/4` (`lib/ancestry/import/csv.ex:144-176`) handles the existing-person branch by calling `People.update_person/2`, which only updates fields. It never calls `People.add_to_family/2`. New people are linked because `People.create_person/2` does the link inside its transaction.

## Fix

In the existing-person branch, after `update_person` (or detecting no changes), call a new helper `People.link_person_to_family/2` that idempotently ensures the person is a member of the current family.

The helper returns:
- `{:ok, :added}` — link was newly created
- `{:ok, :already_linked}` — link already existed (no-op)
- `{:error, reason}` — real error

This is needed because `add_to_family/2` returns `{:error, %Ecto.Changeset{}}` when the unique constraint `[:family_id, :person_id]` is hit, and the import must treat that as a no-op rather than a failure.

## New Counts

The `import_people` accumulator gains two new buckets:

| Field | Meaning |
|-------|---------|
| `people_created` | Brand new in the system. `People.create_person/2` already links them to this family inside its transaction — **no extra `link_person_to_family` call needed for this branch.** |
| `people_added_to_family` | Existed in the system, newly linked to this family by this import |
| `people_already_in_family` | Were already members of this family before the import (link existed) |
| `people_skipped` | Errors |

The summary map keeps `people_unchanged`, `people_updated`, and their name lists for backward compatibility with the mix task printer (no refactor of that code). The new fields are added alongside.

### Counting invariant

A single row can contribute to **both** the existing `unchanged`/`updated` buckets **and** to one of `added_to_family`/`already_in_family`. These are orthogonal facts about the row:

- `unchanged`/`updated` describe whether the person record's fields changed
- `added_to_family`/`already_in_family` describe whether the family link was newly created

The invariant the implementer should preserve:

```
people_created + people_added_to_family + people_already_in_family + people_skipped == row_count
```

The legacy invariant `people_created + people_updated + people_unchanged + people_skipped == row_count` is also preserved (the `created` branch counts only as created; everything else falls into updated or unchanged).

## Modal Labels

The results modal in `lib/web/live/family_live/show.html.heex` is updated with clearer labels and explicit `test_id` mappings (existing `import-existing` is split):

| Label | Value | test_id |
|-------|-------|---------|
| **People created** | `summary.people_created` | `import-created` (kept) |
| **People added to the family** | `summary.people_added_to_family` | `import-added-to-family` (new) |
| **Already in the family** | `summary.people_already_in_family` | `import-already-in-family` (replaces `import-existing`) |
| **Errors** | `summary.people_skipped` | `import-errors` (kept) |

## Implementation Details

### `lib/ancestry/people.ex` — new helper

```elixir
def link_person_to_family(%Person{} = person, family) do
  case add_to_family(person, family) do
    {:ok, _} ->
      {:ok, :added}

    {:error, %Ecto.Changeset{errors: errors}} ->
      if Enum.any?(errors, fn {_k, {msg, _}} -> msg =~ "already" end) do
        {:ok, :already_linked}
      else
        {:error, :link_failed}
      end

    {:error, reason} ->
      {:error, reason}
  end
end
```

### `lib/ancestry/import/csv.ex` — update `import_or_update_person/4`

- Add `added_to_family: 0` and `already_in_family: 0` to the `import_people` initial accumulator
- New person branch: unchanged. `create_person` already links the person inside its transaction; only increments `created`. **Do not call `link_person_to_family` here.**
- Existing person branch — call `link_person_to_family(existing, family)` in **both** sub-branches:
  - **No-change sub-branch** (`changed_fields == []`): increment `unchanged` AND increment `added_to_family` or `already_in_family` based on the link result. This is the most common real-world trigger of the bug — a person already exists in family A unchanged and is being imported into family B.
  - **Update sub-branch** (`changed_fields != []`): after `update_person`, increment `updated` AND increment `added_to_family` or `already_in_family` based on the link result.
- If `link_person_to_family` returns `{:error, reason}`, treat it as a row-level failure: increment `skipped` and append a descriptive error to `errors`. Do not increment `added_to_family`/`already_in_family` in that case.
- Add `people_added_to_family` and `people_already_in_family` to `build_summary/3`

### `lib/web/live/family_live/show.html.heex` — modal labels

Replace the three existing `<dl>` items in the results state with the four new labels listed above.

## Tests

**Unit tests** in `test/ancestry/import/csv_test.exs`:
1. Importing a person that exists in another family **with identical fields** → counts as `added_to_family` (NOT `updated`) and the link is created in the new family (verify via `People.list_people_for_family`). This is the no-change-but-link path that exercises Finding 4.
2. Importing a person that exists in another family **with different fields** → counts as `added_to_family` AND `updated`, link is created.
3. Re-importing the same CSV into the same family → first run counts as `created`, second run counts as `already_in_family` (and `unchanged`).

**Existing tests preserved:** The "reports unchanged people on re-import" and "updates changed people on re-import" tests in `test/ancestry/import/csv_test.exs` will continue to pass because they import twice into the same family, which exercises the `already_in_family` branch and keeps `unchanged`/`updated` counts intact.

**No new E2E test needed.** The existing E2E test exercises the full flow; the bug was only in the count accounting and link side effect, both unit-testable. The E2E test's `test_id("import-created")` assertion is preserved (kept).

## Files Changed

- `lib/ancestry/people.ex` — add `link_person_to_family/2`
- `lib/ancestry/import/csv.ex` — update `import_or_update_person/4`, `import_people/3` accumulator, `build_summary/3`
- `lib/web/live/family_live/show.html.heex` — modal labels
- `test/ancestry/import/csv_test.exs` — new tests

## Out of Scope

- Refactoring the mix task `print_summary/1` to use the new counts (the old `people_unchanged`/`people_updated` fields stay for backward compatibility)
- Wrapping the `update_person` + `link_person_to_family` calls in `Ecto.Multi`. They are independent operations on different schemas; if the link fails after a successful update, the update is preserved, which is the desired behavior. The new project rule about `Ecto.Multi` applies when multiple schema mutations need atomic rollback — not the case here.
