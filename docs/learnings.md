# Learnings

Structured learnings are stored in `docs/learnings.jsonl` — one JSON object per line with fields: `id`, `tags`, `title`, `problem`, `fix`.

## Searching

```bash
# By broad category
grep "liveview" docs/learnings.jsonl
grep "js-hooks" docs/learnings.jsonl
grep "security" docs/learnings.jsonl
grep "testing" docs/learnings.jsonl
grep "silent-failure" docs/learnings.jsonl

# By specific mechanism
grep "handle-event" docs/learnings.jsonl
grep "phx-click" docs/learnings.jsonl

# Pretty-print a specific entry
grep "stable-livecomponent" docs/learnings.jsonl | jq .
```

## Index

| ID | Tags | Title |
|----|------|-------|
| stable-livecomponent-ids | liveview, components, state, mount | LiveComponent IDs must be stable when persisting |
| pure-presentation-components | liveview, components, navigation, design-pattern | Reusable components should not embed navigation |
| partitioned-query-drop | ecto, database, data-integrity, silent-failure | Partitioned queries silently drop records |
| batch-import-idempotent | import, csv, ecto, changeset, error-handling | Batch imports must be idempotent and categorize failures |
| fullwidth-scoped-scroll | layout, css, tailwind, ui, design | Full-width layout with scoped scroll containers |
| clean-test-output | testing, ci, quality, factory | Test output must be clean |
| sort-computed-not-input | elixir, ecto, query, logic, bug | Sorting input field != sorting computed result |
| no-nil-branching | elixir, design-pattern, refactoring, api | No nil-branching in functions |
| update-dependent-assigns | liveview, components, state, handle-event | Event handlers must update dependent assigns |
| js-hook-native-types | liveview, js-hooks, type-coercion, bug | pushEvent sends native types, phx-value sends strings |
| colocated-hooks-otp-name | liveview, js-hooks, build, silent-failure | Colocated hooks resolve under OTP app name |
| safe-dom-in-hooks | liveview, js-hooks, security, xss | Use safe DOM methods in JS hooks |
| assign-async-mount | liveview, ecto, testing, performance, race-condition | Expensive mount queries cause test race conditions |
| svg-currentcolor-visibility | ui, css, tailwind, svg, visual-bug, silent-failure | SVG currentColor invisible when matching background |
| hook-data-attr-sync | liveview, js-hooks, server-client-sync, silent-failure | JS hooks must handle all data-* variants |
| router-on-mount-hooks | liveview, phoenix, router, authentication, architecture | Router-level on_mount hooks for tenant enforcement |
| phx-click-away | liveview, ui, events, event-bubbling | Use phx-click-away for dropdowns |
| checkbox-uncheck-empty-params | liveview, events, forms, bug | Checkbox phx-click sends empty params on uncheck |
| layout-attr-passthrough | liveview, components, layout, silent-failure | Layout attrs must be passed from every call site |
