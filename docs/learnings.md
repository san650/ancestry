# Learnings

## LiveComponent IDs must be stable when the component should persist

When a LiveComponent's `id` is derived from changing data (e.g., `id={"panel-#{@selected_item.id}"}`), Phoenix treats each new id as a different component. It destroys the old instance and mounts a new one instead of calling `update/2` on the existing one. This can cause the component to show stale content or fail to refresh when the parent's assigns change.

**Fix:** Use a stable id (e.g., `id="panel"`) when the component should persist across assign changes. The component's `update/2` callback receives the new assigns and can reload its data. Reserve dynamic ids for cases where you intentionally want a fresh component instance per item.

## Reusable components should not embed navigation behavior

When a component like `person_card` wraps its content in `<.link navigate={...}>`, it cannot be reused in contexts where a different click behavior is needed (e.g., a `<button phx-click="select_person">` in a modal). The `<.link navigate>` fires client-side navigation before any `phx-click` on a parent element reaches the server, causing the page to navigate away unexpectedly.

**Fix:** Make reusable display components pure presentation (`<div>` wrappers, no click behavior). Let each call site decide the interaction: `<.link navigate>` for navigation, `<button phx-click>` for events, or nothing for display-only contexts. This follows the principle of separating presentation from behavior.

## Partitioned queries with implicit exclusion can silently drop records

When displaying related records by splitting them across multiple specialized queries (e.g., "children of this pair" + "children with no second parent"), any record that doesn't match *either* query becomes invisible. This is especially dangerous when the partitions rely on external state (e.g., whether two parents are linked as partners) — changing that state silently hides records that were previously visible.

**Fix:** Use a single comprehensive query that returns all records, then group/partition in memory. This guarantees no record is missed regardless of external state. Each bucket's filter logic is explicit and testable in one place.

## Batch import output should categorize failures, not just count them

When a batch import (e.g., CSV import) skips records, printing only aggregate counts like "Relationships skipped: 143" makes it impossible to diagnose what went wrong. Different skip reasons (duplicates, missing references, constraint violations) require different responses — duplicates are expected and harmless, while missing references indicate data problems.

**Fix:** Categorize failures into expected skips (e.g., duplicate symmetric relationships) and real errors (missing references, constraint violations). Print expected skips as a single summary count and real errors as individual lines with enough context to identify the affected records (e.g., external IDs, relationship type).
