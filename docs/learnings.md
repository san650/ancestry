# Learnings

## LiveComponent IDs must be stable when the component should persist

When a LiveComponent's `id` is derived from changing data (e.g., `id={"panel-#{@selected_item.id}"}`), Phoenix treats each new id as a different component. It destroys the old instance and mounts a new one instead of calling `update/2` on the existing one. This can cause the component to show stale content or fail to refresh when the parent's assigns change.

**Fix:** Use a stable id (e.g., `id="panel"`) when the component should persist across assign changes. The component's `update/2` callback receives the new assigns and can reload its data. Reserve dynamic ids for cases where you intentionally want a fresh component instance per item.
