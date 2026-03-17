# CSV Import Design

## Goal

Create a mix task to import people and relationships from a CSV file into a new family. The design uses an adapter pattern so different CSV formats (e.g., FamilyEcho) can be supported.

## Usage

```
mix ancestry.import_csv family_echo "Ferreira Family" path/to/family.csv
```

## Module Structure

```
lib/ancestry/
  import.ex                    # Ancestry.Import — public API entry point
  import/
    csv.ex                     # Ancestry.Import.CSV — generic CSV logic
    csv/
      family_echo.ex           # Ancestry.Import.CSV.FamilyEcho — FamilyEcho adapter
```

### Ancestry.Import

Public entry point. Single function:

- `import_from_csv(adapter, family_name, csv_path)` — delegates to `Ancestry.Import.CSV`

### Ancestry.Import.CSV

Generic CSV import logic. Defines adapter behaviour callbacks:

- `parse_person(row :: map()) :: {:ok, map()} | {:skip, reason}` — returns normalized person attrs
- `parse_relationships(row :: map()) :: [relationship_tuple]` — returns list of `{type, source_external_id, target_external_id, metadata}`

Orchestrates the import flow:

1. Validate inputs (file exists, adapter module valid)
2. Create family via `Families.create_family/1`
3. Parse CSV with `NimbleCSV`
4. **Pass 1 — People**: For each row, call adapter's `parse_person/1`, create person via `People.create_person/2`, track successes/failures
5. **Pass 2 — Relationships**: For each row, call adapter's `parse_relationships/1`, look up people by `external_id`, create via `Relationships.create_relationship/4`, skip if either person not found
6. Return summary: `{:ok, %{family: family, people_created: N, people_skipped: N, relationships_created: N, relationships_skipped: N, errors: [...]}}`

### Ancestry.Import.CSV.FamilyEcho

Implements the adapter behaviour for FamilyEcho CSV exports.

**Person mapping:**

| CSV Column | Person field |
|---|---|
| `ID` | `external_id` (prefixed `"family_echo_"`) |
| `Given names` | `given_name` |
| `Surname now` | `surname` |
| `Surname at birth` | `surname_at_birth` |
| `Nickname` | `nickname` |
| `Title` | `title` |
| `Suffix` | `suffix` |
| `Gender` | `gender` — "Female"→"female", "Male"→"male", else "other" |
| `Deceased` | `living` — "Y"→"no", else "yes" |
| `Birth year/month/day` | `birth_year`, `birth_month`, `birth_day` (integers) |
| `Death year/month/day` | `death_year`, `death_month`, `death_day` (integers) |

Rows where both `Given names` and `Surname now` are blank → `{:skip, "no name"}`.

**Relationship mapping:**

- `Mother ID` → `{:parent, mother_external_id, person_external_id, %{role: "mother"}}`
- `Father ID` → `{:parent, father_external_id, person_external_id, %{role: "father"}}`
- `Partner ID` → `{:partner, person_external_id, partner_external_id, %{}}`
- `Ex-partner IDs` (comma-separated) → multiple `{:ex_partner, person_external_id, ex_external_id, %{}}` tuples

Blank referenced IDs are skipped.

## Data Model Change

Add `external_id` string field to the `persons` table:

- Migration: `add :external_id, :text` with unique index
- Schema: `field :external_id, :string` (optional, only set during imports)
- Format: `"family_echo_#{csv_id}"`, e.g. `"family_echo_KICCA"`

## New Dependency

`nimble_csv` — for robust CSV parsing (handles quoted fields, embedded commas).

## Mix Task

`Mix.Tasks.Ancestry.ImportCsv` — thin CLI wrapper:

- Validates 3 args: adapter name, family name, CSV path
- Maps adapter string to module (`:family_echo` → `Ancestry.Import.CSV.FamilyEcho`)
- Calls `Ancestry.Import.import_from_csv/3`
- Prints human-readable summary

**Error handling:**

- Wrong arg count → usage instructions
- Unknown adapter → list available adapters
- File not found → error message
- Family creation failure → error message

**Import strategy:** Best-effort — imports what it can, skips bad rows/relationships, prints summary with skip reasons.
