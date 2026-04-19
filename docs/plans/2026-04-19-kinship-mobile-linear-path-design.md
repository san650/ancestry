# Kinship Mobile Linear Path View

**Date:** 2026-04-19
**Status:** Approved

## Problem

The kinship path visualization uses an inverted-V tree layout (MRCA at top, fork into two side-by-side branches). On mobile (below `md` breakpoint), the branches stack vertically via `flex-col` but still render as two separate halves of the tree — the fork connector and split layout don't read well on narrow screens.

## Solution

Add a responsive mobile alternative that renders the kinship path as a single unified top-to-bottom linear column. Desktop keeps the existing forked tree.

## Layout Strategy

- **Desktop (`md:` and up):** Existing inverted-V tree layout unchanged, wrapped in `hidden md:block`.
- **Mobile (below `md:`):** New `md:hidden` block renders a single vertical column:

```
Person A  (highlighted endpoint)
    ↓
Parent of A
    ↓
MRCA  (highlighted, "Common Ancestor" label)
    ↓
Parent of B
    ↓
Person B  (highlighted endpoint)
```

Each node uses the existing `kinship_person_node` component. Between each node is the existing `arrow_connector` with `direction={:down}` (always top-to-bottom). The MRCA gets highlighted styling (`bg-ds-primary/10 border-ds-primary/30`) plus its "Common Ancestor" extra label — this is a deliberate visual difference from desktop where only endpoints are highlighted, to help the MRCA stand out in the middle of a linear flow.

## Path Merging Logic

Built purely in the template by concatenating existing assigns — no new LiveView assigns.

**Two-branch case** (both `path_a` and `path_b` have multiple nodes):
- Render `path_a` in **reverse order** (the assign stores MRCA-first, so reverse to get Person A at top → MRCA at bottom)
- Render `path_b` starting from index 1 (skip MRCA to avoid duplication)
- Arrow direction is always `:down`

**Direct line case** (one side has 1 node): Already renders as a single vertical column — no changes needed. The direct-line `cond` branch is NOT wrapped in `hidden md:block`; only the two-branch clause gets the responsive wrapper.

**In-law paths — side `:b`** (partner hop on B's side):
```
Person A  (highlighted)
    ↓
Grandparent
    ↓
MRCA  (highlighted, "Common Ancestor")
    ↓
Parent
    ↓
Partner      ← stacked vertically
  ↕ icon
Person B     ← highlighted
```

**In-law paths — side `:a`** (partner hop on A's side):
```
Person A     ← highlighted
  ↕ icon
Partner      ← stacked vertically
    ↓
Grandparent
    ↓
MRCA  (highlighted, "Common Ancestor")
    ↓
Person B  (highlighted)
```

Partner pair detection: nodes with `partner_link?: true` are grouped and rendered as a stacked pair unit (not as individual nodes with arrows between them). A single down-arrow connector appears before/after the pair unit as a whole.

**Direct spouse case** (both paths <= 1 node, in-law): Currently renders as a single `partner_pair_node` side-by-side. On mobile, this also stacks vertically using the same vertical partner pair rendering.

## Component Changes

**No new components.** Reuse existing:

- `kinship_person_node` — unchanged
- `arrow_connector` — unchanged, always `direction={:down}` in mobile view
- `partner_pair_node` — add `direction` attr (`:horizontal` default for desktop, `:vertical` for mobile). When vertical, renders as stacked column with rotated ↔ icon. This is a minor change to the component defined in `kinship_live.ex`.

**Template changes — `kinship_live.html.heex`:**

1. Wrap the two-branch tree `cond` clause (not the direct-line clause) in `hidden md:block`
2. Add sibling `md:hidden` block with linear column rendering
3. Wrap the in-law two-branch tree block in `hidden md:block` and add mobile equivalent
4. Wrap the direct spouse `partner_pair_node` in `hidden md:block` and add vertical mobile equivalent

**`kinship_live.ex` changes:** Minor — add `attr :direction, :atom, default: :horizontal` to `partner_pair_node` component and conditional layout logic.

**No changes to:** `kinship.ex`, CSS, or JS files.

## Edge Cases

- **Direct line paths:** Already a single column, no mobile variant needed — the direct-line `cond` branch is left unwrapped
- **Single-hop relationships:** Two nodes, one arrow — works naturally
- **Long paths:** Column scrolls with the page
- **Partner pairs in in-law paths:** Stack vertically on mobile, horizontal on desktop
- **Direct spouse (both paths <= 1):** Stacks vertically on mobile
- **Test IDs:** If `test_id("kinship-path")` exists on the container, use distinct IDs (`kinship-path-desktop`, `kinship-path-mobile`) to avoid duplicate selector matches
- **Accessibility:** Use Tailwind `hidden` class (which sets `display: none`) so hidden DOM trees are excluded from the accessibility tree — do not use `invisible` or `opacity-0`

## Approach

CSS-only responsive using Tailwind `hidden md:block` / `md:hidden`. Two DOM trees rendered (one hidden per breakpoint). Node count is small so overhead is negligible. No JS hooks or viewport detection needed.
