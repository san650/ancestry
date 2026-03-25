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

## Batch imports must handle re-runs gracefully

When a batch import uses a unique external ID to track imported records, re-running the import will crash with a constraint error if the changeset doesn't declare `unique_constraint/3`. Even with the constraint declared, the import logic should check for existing records before attempting insertion to provide meaningful feedback ("already exists" vs a cryptic changeset error).

**Fix:** Always add `unique_constraint` to changesets for fields with unique DB indexes. For idempotent imports, look up by external ID first: if the record exists and data matches, report it as unchanged; if data differs, update it and report what changed; if it doesn't exist, create it. For the parent entity (e.g., family), use find-or-create by name.

## Page layout should be full-width with scoped scroll containers

Pages should go edge-to-edge with no padding on `<main>`. Each page controls its own internal spacing. Horizontal scroll should only exist on specific content containers (e.g., a tree canvas), never on the full page — use `overflow-x-hidden` on the outer wrapper and `overflow-x-auto` on the scrollable container. Vertical scroll should be page-level (the browser's natural scroll behavior), not constrained to individual containers.

**Fix:** When adding a new page, do not add `overflow-y-auto` or `max-h-screen` to content containers. Let the page grow naturally. Only add `overflow-x-auto` to containers whose content may exceed the viewport width.

## Test output must be clean — no hanging log errors or warnings

After implementing a feature or bugfix, the test suite output should contain only test results — no `[error]` log lines, no `[warning]` noise, no 404s from missing resources. Noisy test output hides real problems and normalizes ignoring errors.

Common causes: E2E tests rendering `<img>` tags for files that don't exist on disk (factories create DB records with `status: "processed"` but no actual files), or test configs that route file storage to a different directory than where the web server serves static files.

**Fix:** Always verify clean output with `mix test 2>&1 | grep "\[error\]"` before considering a task complete. When tests create records that reference files, ensure the files exist where the server expects them — either by aligning storage paths, adding test-only static file serving, or creating placeholder files in test setup.

## Sorting by input field is not the same as sorting by computed result

When finding the "max" of a derived value (e.g., age = end_date - start_date), sorting by one of the inputs (e.g., earliest start_date) only works if the other input is constant for all candidates. If both inputs vary (e.g., deceased people have different end dates than living people), the derived value must be computed for each candidate and the max selected explicitly.

**Fix:** Load all eligible candidates, compute the derived value for each in application code, then pick the max. For small datasets (family trees), the overhead is negligible and the logic stays in one place rather than being split between SQL and application code.

## Functions that accept nil to branch behavior are an anti-pattern

When a function accepts a parameter that may be `nil` and uses `if`/`case` to branch into fundamentally different behavior (e.g., `search(query, family_id)` where `family_id: nil` means "search globally" and a value means "search within family"), the function is doing two jobs under one name. This hides intent, makes the call site ambiguous, and makes the function harder to reason about.

**Fix:** Create two functions with descriptive names that each do one thing: `search_family_members/3` for family-scoped search and `search_all_people/2` for global search. Similarly, `create_person_wtih_family/2` and `create_person_without_family/1` (standalone). Let the caller choose the right function explicitly. Pattern matching on struct vs no-struct in function heads is acceptable for dispatch, but the distinct behaviors should have distinct names in the public API.

## Event handlers that change state must update all dependent assigns

When a LiveView event handler modifies state that other assigns depend on (e.g., setting a default person that should trigger a tree to render), it must also update those dependent assigns in the same response. LiveView's `handle_params/3` only runs on mount and URL changes — not after event handlers. So if the tree rendering logic lives only in `handle_params`, saving a default person in a `handle_event` won't trigger the tree to appear until the user navigates away and back.

**Fix:** After modifying state in an event handler, also update any assigns that derive from that state. If the same derivation logic is needed in both `handle_params` and `handle_event`, extract it to a shared private function and call it from both places.

## JS hook pushEvent sends native types, phx-value-* sends strings

When a JS hook calls `this.pushEvent("event", { id: 42 })`, the value arrives in the Elixir `handle_event` as an integer (`42`), not a string. Calling `String.to_integer(42)` raises `ArgumentError: not a binary`. In contrast, `phx-value-*` HTML attributes always arrive as strings because they go through DOM serialization (`phx-value-id="42"` → `%{"id" => "42"}`).

**Fix:** When a `handle_event` receives values from JS hooks, don't assume they're strings. Either ensure the JS side sends strings (`person_id: String(person.id)`) or handle both types on the server. The cleanest approach is to normalize in the JS hook — always send string values to match the convention of `phx-value-*` attributes, so all event handlers can consistently use `String.to_integer/1`.

## Colocated JS hooks resolve under the OTP app name, not the project directory name

Phoenix LiveView colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook}>`) are compiled into `_build/{env}/phoenix-colocated/{otp_app}/`. The import in `app.js` must use the **OTP app name** (e.g., `"phoenix-colocated/ancestry"`), not the project directory name (e.g., `"phoenix-colocated/family"`). If these don't match, the import resolves to a stale or empty index and hooks silently fail to register — they compile without errors but don't work at runtime.

**Fix:** For reliability, define hooks as plain JS objects in `assets/js/` files, import them in `app.js`, and pass them to the `LiveSocket` constructor's `hooks` option. This avoids the colocated hooks build pipeline entirely and makes hook registration explicit and debuggable. Reserve colocated hooks for trivial inline scripts where the build pipeline indirection isn't a concern.

## Use safe DOM methods instead of string-based HTML in JS hooks

When building DOM dynamically in LiveView JS hooks (e.g., rendering search results in a popover), using string-based HTML construction with interpolated data (even database-sourced data) triggers security warnings and risks XSS if the data ever contains HTML. Pre-commit hooks and CI security scanners will flag this.

**Fix:** Use safe DOM construction methods: `document.createElement`, `element.textContent = value`, `element.appendChild`. For clearing containers, use `element.replaceChildren()`. This eliminates XSS vectors entirely and satisfies security linters.

## Expensive queries in LiveView mount cause DB connection race conditions in tests

When `mount/3` runs multiple sequential DB queries synchronously, the LiveView process holds the test's sandbox DB connection for the entire duration. If the test process exits before mount completes (e.g., the test navigates away, causing a new LiveView to mount), the connection owner dies while the LiveView is still querying, producing `owner exited` errors.

**Fix:** Use `assign_async/3` for expensive or non-critical data loading (like metrics, aggregations, or analytics). This moves the queries into a supervised async task that is properly cleaned up on process termination. The template renders immediately with a loading state, and the data appears when ready. When re-assigning the same data synchronously elsewhere (e.g., after a user action that changes the underlying data), wrap the result with `Phoenix.LiveView.AsyncResult.ok(value)` to maintain a consistent type for the template.

## SVG elements inherit color from CSS `color` property via `currentColor` — verify the color class is visible

When using `stroke="currentColor"` on SVG elements inside a Tailwind-styled container, the SVG stroke color is controlled by the container's `text-*` class. If the text color class matches the background color (e.g., `text-base-200` on a `base-200` background), the SVG will render but be invisible. This is easy to miss because the SVG element is present in the DOM and passes structural tests.

**Fix:** Always verify SVG color classes against the actual background. Use a color that provides visible contrast (e.g., `text-base-300` or `text-base-content/30`). When replacing simple CSS connectors (borders, divs) with SVG connectors, test visibility visually — structural/DOM tests won't catch invisible-but-present elements.

## JS hooks must handle all data attribute variants they consume

When server-side code tags elements with different `data-*` prefixes to distinguish groups (e.g., `data-line-origin="partner"`, `data-line-origin="ex-{id}"`, `data-line-origin="prev-{id}"`), the JS hook that reads these attributes must have handlers for every variant. If a new variant is introduced on the server side (e.g., adding `"prev-"` for previous partners) but the JS hook's dispatch logic isn't updated, the new variant silently falls through to a default/fallback — producing incorrect behavior without any error.

**Fix:** When adding a new data attribute variant on the server side, always grep the JS hooks that consume the attribute and add matching handlers. The server-side `data-*` attributes and the JS hook's conditional branches must stay in sync. Consider adding a comment in the JS listing all expected prefixes so the next person knows to update both sides.

## Use router-level on_mount hooks for tenant enforcement across live_sessions

When multiple LiveViews need the same cross-cutting concern — loading a tenant entity from URL params, enforcing sandbox access in tests — register `on_mount` hooks at the `live_session` level in the router, not inside individual LiveView modules. Router-level hooks run before module-level hooks, and their ordering is guaranteed: hooks listed first in the `on_mount:` list run first.

This matters for hook ordering: if an Ecto sandbox hook must run before a tenant-loading hook (because the tenant hook queries the database), both must be at the router level with the sandbox hook listed first.

**Fix:** Define on_mount hooks as standalone modules, then compose them in the router's `live_session`:

```elixir
# router.ex
@sandbox_hooks if(Application.compile_env(:ancestry, :sql_sandbox),
                 do: [Web.LiveAcceptance],
                 else: []
               )

live_session :default, on_mount: @sandbox_hooks do
  live "/", OrganizationLive.Index, :index
end

scope "/org/:org_id" do
  live_session :organization, on_mount: @sandbox_hooks ++ [Web.EnsureOrganization] do
    live "/", FamilyLive.Index, :index
    ...
  end
end
```

This keeps LiveView modules free of boilerplate — they just access `socket.assigns.organization` which is guaranteed to be set by the hook before `mount/3` runs.

## Parent click handlers close child dropdowns via event bubbling

Placing `phx-click="close"` on a parent container to implement click-away behavior causes clicks on child elements (like search inputs inside a dropdown) to bubble up and trigger the close event, immediately closing the dropdown the user is trying to interact with.

**Fix:** Use `phx-click-away` on the dropdown element itself instead of `phx-click` on a parent container. `phx-click-away` fires only when the click is *outside* the annotated element, so clicks within the dropdown (search field, options) work normally. For autofocusing inputs that appear dynamically (via LiveView patching), use `phx-mounted={JS.focus()}` instead of the HTML `autofocus` attribute, which only works on initial page load.

## Checkbox `phx-click` with `phx-value-*` sends empty params on uncheck

When using `phx-click` with `phx-value-value` on a checkbox, unchecking sends an empty map `%{}` — not `%{"value" => "false"}`. The `phx-value-*` attributes are only included in the event payload when the element's click fires with a truthy interaction, but the uncheck action sends no value attributes.

**Wrong** — pattern matching on `%{"value" => value}` crashes with `FunctionClauseError` on uncheck:

```elixir
def handle_event("toggle_option", %{"value" => value}, socket) do
  {:noreply, assign(socket, :option, value == "true")}
end
```

**Fix:** Accept any params and use bracket access (`params["value"]`), which returns `nil` for missing keys. `nil == "true"` evaluates to `false`, correctly representing an unchecked checkbox:

```elixir
def handle_event("toggle_option", params, socket) do
  {:noreply, assign(socket, :option, params["value"] == "true")}
end
```

## Layout component attrs must be explicitly passed from every call site

When a Phoenix layout component (e.g., `Layouts.app`) declares an attr with `default: nil`, any template that omits that attr will silently get `nil` instead of the socket assign. This causes conditional rendering blocks (like `if @current_scope && @current_scope.account`) to silently fail — the links simply don't appear, with no compile-time or runtime error.

**Fix:** After adding a new attr to a shared layout component, grep all call sites (`Layouts.app` in templates) and ensure every one passes the attr. The `on_mount` hook assigns the value to the socket, but Phoenix components are explicit — socket assigns are not automatically forwarded to component attrs.
