# CSV Import from Family Show Page

## Summary

Add a meatball (three-dot) overflow menu to the family show toolbar on desktop. The menu consolidates secondary actions: **Manage People**, **Create Subfamily**, and a new **Import from CSV** option. All three are hidden on mobile entirely.

Selecting "Import from CSV" opens a modal that accepts a CSV file, runs the import pipeline synchronously, and displays a people-only results summary.

## Meatball Menu

- Desktop-only (`hidden lg:block`), positioned at the end of the toolbar action buttons (after Delete).
- Three-dot icon button toggles a dropdown via a `:show_menu` boolean assign.
- `phx-click-away` closes the dropdown.
- Menu items (icon + label rows):
  1. **Manage People** — existing `hero-user-group` action, moved from toolbar
  2. **Create Subfamily** — existing `hero-square-2-stack` action, moved from toolbar (conditional on families existing)
  3. **Import from CSV** — new action, `hero-arrow-up-tray` or similar

Existing event handlers for Manage People and Create Subfamily remain unchanged; only their trigger location moves.

## Import Modal

Two-state modal, following the project's existing modal pattern (`items-end lg:items-center`, `rounded-t-lg lg:rounded-ds-sharp`).

### State 1: Upload Form

- Title: "Import from CSV"
- Format selector: `<.input type="select">` with "Family Echo" as the only option (pre-selected). This is a visual indicator of the format being used and leaves room for future adapters. The pipeline always receives `:family_echo` for now.
- File upload: `allow_upload` for `.csv` files, single file, max 10MB
- "Import" button (disabled until a file is selected)
- "Cancel" button to close

### State 2: Results

After import completes, the modal swaps to show:

- **People added:** `summary.people_created`
- **People already existing:** `summary.people_unchanged + summary.people_updated`
- **Errors:** `summary.people_skipped`
- If errors exist: scrollable list (`max-h-60 overflow-y-auto`) of `summary.people_errors`
- "Close" button to dismiss

Relationships are still imported by the pipeline; we just don't display those counts.

## Data Flow

1. User selects file, clicks "Import".
2. Inside the `consume_uploaded_entries` callback, the uploaded file is available at the LiveView-managed temp path (`meta.path`).
3. Call `Ancestry.Import.CSV.import_for_family/3` (new function — see below) with the adapter module, the already-loaded family struct, and the temp path. This runs synchronously inside the callback.
4. Store the summary map in assigns; modal flips to results state. No temp file cleanup needed — LiveView manages the upload temp file lifecycle.
5. On modal close: re-assign `:people`, `:tree`, and `:metrics` to refresh the side panel, clear all import-related assigns (`:import_summary`, `:show_import_modal`).

## Import Pipeline Adaptation

The existing `CSV.import/4` takes `(adapter_module, family_name, csv_path, org)` and uses `find_or_create_family` to look up the family by name. This is fragile — name collisions across organizations would cause incorrect matches or crashes.

**New function:** Add `Ancestry.Import.CSV.import_for_family/3` that accepts `(adapter_module, %Family{} = family, csv_path)` — bypassing the name-based lookup entirely. This extracts the parsing and import logic from `import/4`, keeping both entry points working:

- `CSV.import/4` — used by the mix task (unchanged behavior)
- `CSV.import_for_family/3` — used by the LiveView (accepts family struct directly)

**New dispatcher:** Add `Ancestry.Import.import_csv_for_family/3` that maps adapter name to module and delegates to `CSV.import_for_family/3`.

### Files modified:
- `lib/ancestry/import.ex` — add `import_csv_for_family/3`
- `lib/ancestry/import/csv.ex` — add `import_for_family/3`, extract shared logic

## Error Handling

- `{:error, reason}` from the import pipeline: shown inside the modal as an error state with the reason and a "Close" button. The modal does not auto-close on error.
- NimbleCSV parse failures (malformed CSV content): the `import_csv_for_family` call is wrapped in `try/rescue` in the LiveView event handler. Parse crashes are caught and shown as an error in the modal (e.g., "Could not parse CSV file").
- File validation (wrong extension, too large): handled by Phoenix upload validation before import runs, shown as upload errors inline.

## Changes Required

### Files modified:
- `lib/ancestry/import.ex` — add `import_csv_for_family/3` dispatcher
- `lib/ancestry/import/csv.ex` — add `import_for_family/3`, extract shared import logic
- `lib/web/live/family_live/show.ex` — add `:show_menu` and import assigns, `allow_upload`, new event handlers (`toggle_menu`, `open_import`, `import_csv`, `close_import`), refresh people/tree/metrics on completion. Extract `org` from `socket.assigns.current_scope.organization`.
- `lib/web/live/family_live/show.html.heex` — replace Manage People + Create Subfamily toolbar buttons with meatball dropdown; add import modal markup

### No new files needed.

## Mobile Behavior

The meatball menu and all three actions within it (Manage People, Create Subfamily, Import from CSV) are hidden on mobile. Mobile users continue to use the nav drawer for Edit, Kinship, and Delete actions only.
