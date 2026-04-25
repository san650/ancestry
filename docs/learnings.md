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
| mobile-toolbar-pattern | liveview, layout, mobile, responsive, toolbar, design-pattern | Toolbar actions go desktop-only; mobile uses nav drawer |
| drawer-action-close-drawer | liveview, ui, mobile, drawer, js, design-pattern, silent-failure | Drawer actions that change the main canvas must dismiss the drawer |
| audit-generated-auth-defaults | security, authentication, scaffold, threat-model | Audit auth scaffolder defaults against your threat model |
| post-commit-side-effect-cleanup | ecto, atomicity, transactions, file-cleanup, storage, cascade | Pre-collect side effects, mutate DB, then clean up only on commit |
| hook-destroyed-must-guard-state | liveview, js-hooks, lifecycle, destroyed, silent-failure | JS hook destroyed() must guard against state mounted() may not have set |
| playwright-transform-vs-visibility | testing, playwright, e2e, css, drawers, selectors | Playwright considers transform-translated elements visible |
| use-descriptive-fk-names | ecto, database, schema, naming, readability | Use descriptive FK column names over generic entity_id |
| template-struct-field-blind-spot | liveview, heex, templates, testing, silent-failure | Template struct field access is a runtime-only failure — compile and unit tests miss it |
| checkbox-server-state-revert | liveview, forms, checkbox, phx-change, state, silent-failure | Checkboxes with server-controlled checked attr revert on phx-change |
| playwright-dual-responsive-layout | testing, playwright, e2e, css, responsive, silent-failure | Playwright assert_has fails on responsive dual-layout components |
| stream-items-outer-assign | liveview, streams, phx-update, handle-event, silent-failure | Stream items don't re-render when only an outer assign changes |
| phx-no-format-whitespace-pre | liveview, heex, formatter, css, whitespace, silent-failure | Use phx-no-format when an element has whitespace-pre-line or whitespace-pre-wrap |
| phx-value-empty-string | liveview, phx-value, phx-click, type-coercion, bug | phx-value-* can send empty strings on disabled/re-rendered buttons |
| morphdom-stable-ids-for-loops | liveview, morphdom, dom-patching, for-loops, silent-failure | for-loop items need stable IDs when content changes across renders |
| at-limit-simplified-path-data-loss | elixir, tree-view, silent-failure, code-path-divergence | Simplified code paths at boundaries silently drop data |
| pgettext-gendered-adjectives | i18n, gettext, spanish, gender, pgettext, translation | Use pgettext contexts for gendered adjectives in Spanish |
| hook-mounted-scroll-timing | liveview, js-hooks, scroll, live-navigation, timing | JS hook scrollIntoView fails on live navigation without requestAnimationFrame |
| phx-change-bare-input | liveview, forms, phx-change, phx-keyup, silent-failure | phx-change on a bare input outside a form does not fire events |
