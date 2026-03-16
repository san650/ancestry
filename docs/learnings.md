# Learnings

## LiveComponent IDs must be stable when the component should persist

When a LiveComponent's `id` is derived from changing data (e.g., `id={"panel-#{@selected_item.id}"}`), Phoenix treats each new id as a different component. It destroys the old instance and mounts a new one instead of calling `update/2` on the existing one. This can cause the component to show stale content or fail to refresh when the parent's assigns change.

**Fix:** Use a stable id (e.g., `id="panel"`) when the component should persist across assign changes. The component's `update/2` callback receives the new assigns and can reload its data. Reserve dynamic ids for cases where you intentionally want a fresh component instance per item.

## Reusable components should not embed navigation behavior

When a component like `person_card` wraps its content in `<.link navigate={...}>`, it cannot be reused in contexts where a different click behavior is needed (e.g., a `<button phx-click="select_person">` in a modal). The `<.link navigate>` fires client-side navigation before any `phx-click` on a parent element reaches the server, causing the page to navigate away unexpectedly.

**Fix:** Make reusable display components pure presentation (`<div>` wrappers, no click behavior). Let each call site decide the interaction: `<.link navigate>` for navigation, `<button phx-click>` for events, or nothing for display-only contexts. This follows the principle of separating presentation from behavior.
