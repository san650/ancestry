---
date: 2026-04-19
topic: breadcrumbs
---

# Breadcrumbs — Replace Back Arrows with Contextual Breadcrumbs

## What We're Building

Replace all back arrow buttons (desktop toolbar arrows + mobile FABs) with breadcrumb navigation that shows the user's position in the hierarchy: Organization → Family → Page. Each segment is a link. The breadcrumb reflects where the user came from (preserving existing contextual routing like `from_family` / `from_org`).

## Layout

**Desktop** — breadcrumb replaces the back arrow in the toolbar, inline before the page title:

```
[Org Name] / [Family Name] / Page Title          [actions]
```

All segments except the last are links. The last segment (current page) is the page title, styled bold/prominent.

**Mobile** — breadcrumb appears as small text below the page title in the header:

```
Page Title
[Org Name] / [Family Name]
```

The page title is bold/large. The breadcrumb trail (ancestors only, no current page) is small text below it. Each ancestor segment is a link. The mobile FAB back button is removed.

## Breadcrumb per Page

| Page | Breadcrumb | Notes |
|------|-----------|-------|
| Family Show | `Org` / **Family** | |
| Gallery Show | `Org` / `Family` / **Gallery** | |
| Person Show (from family) | `Org` / `Family` / **Person** | Uses `from_family` context |
| Person Show (from org people) | `Org` / `People` / **Person** | Uses `from_org` context |
| Person Show (default) | `Org` / **Person** | Fallback |
| Kinship | `Org` / `Family` / **Kinship** | |
| People (family-scoped) | `Org` / `Family` / **People** | |
| People (org-scoped) | `Org` / **People** | |
| New Family | `Org` / **New Family** | |
| New Member | `Org` / `Family` / **New Member** | |
| Vault Show | `Org` / `Family` / **Vault** | |
| Memory Form | `Org` / `Family` / **Memory** | |

## Key Decisions

- **Contextual routing preserved**: Person page breadcrumb changes based on `from_family` / `from_org` params, matching existing back-button behavior
- **Shared component**: A single `breadcrumb` function component in `core_components.ex` (or a dedicated `breadcrumb.ex`) takes a list of `%{label: string, navigate: path}` items
- **Last item = page title**: The current page is the last breadcrumb segment, rendered as the title (bold, not a link) — avoids duplicating the page title
- **Mobile FABs removed**: All fixed-position back FABs deleted
- **Desktop back arrows removed**: All `hero-arrow-left` toolbar buttons deleted
- **Separator**: `/` character with muted color between segments
- **Truncation**: On mobile, long org/family names truncate with `text-ellipsis` to prevent overflow

## Component API

```heex
<.breadcrumb items={[
  %{label: @current_scope.organization.name, navigate: ~p"/org/#{@current_scope.organization.id}"},
  %{label: @family.name, navigate: ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}"}
]} current={@person.name} />
```

**Desktop rendering** (inside toolbar `flex items-center`):
```
Org Name  /  Family Name  /  Person Name
(link)       (link)          (bold, no link)
```

**Mobile rendering** (in toolbar, stacked):
```
Person Name          (text-base font-semibold)
Org Name / Family Name   (text-xs text-muted, links)
```

## Open Questions

None — ready for planning.

## Next Steps

→ Plan implementation: create component, update each page template
