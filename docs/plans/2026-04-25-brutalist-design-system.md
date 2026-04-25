# Brutalist Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current blue-tinted neutral design system (ds-* tokens, daisyUI, Manrope/Inter) with a brutalist design using the ColorHunt palette, Bebas Neue/Space Grotesk/Space Mono typography, and custom components.

**Architecture:** New `palette.css` file defines all `--cm-*` CSS variables. Tailwind `@theme` block registers them as utility classes. A global token migration replaces all `ds-*` references with `cm-*` equivalents. Then each page is restyled to match the brutalist spec.

**Tech Stack:** Tailwind CSS v4, Phoenix LiveView, self-hosted Google Fonts (woff2), SVG logo

**Spec:** `docs/plans/2026-04-25-brutalist-design-system-design.md`

---

## File Map

### New files
- `assets/css/palette.css` — all `--cm-*` variables and utility classes
- `priv/static/fonts/bebas-neue.woff2` — display font
- `priv/static/fonts/space-grotesk-variable.woff2` — body font
- `priv/static/fonts/space-mono-regular.woff2` — mono font
- `priv/static/fonts/space-mono-bold.woff2` — mono font bold
- `priv/static/images/logo.svg` — new brutalist logo (replaces existing)
- `priv/static/favicon.ico` — new favicon (replaces existing)

### Deleted files
- `assets/vendor/daisyui.js` — daisyUI plugin
- `priv/static/fonts/manrope-variable.woff2` — old heading font
- `priv/static/fonts/inter-variable.woff2` — old body font

### Modified files (by task)

**Task 1 — CSS foundation:**
- `assets/css/app.css`
- `assets/css/palette.css` (new)

**Task 2 — Font files:**
- `priv/static/fonts/` (new font files)

**Task 3 — Global token migration (46 files):**
- All `.ex` and `.heex` files containing `ds-` tokens (see inventory below)

**Task 4 — Core components (buttons, flash, inputs):**
- `lib/web/components/core_components.ex`

**Task 5 — Layout, mobile, nav components:**
- `lib/web/components/layouts.ex`
- `lib/web/components/mobile.ex`
- `lib/web/components/nav_drawer.ex`
- `lib/web/components/avatar_components.ex`
- `lib/web/components/layouts/root.html.heex` (no ds- tokens, but needs font/bg class updates)

**Task 6 — Photo gallery:**
- `lib/web/components/photo_gallery.ex`

**Task 7 — Logo & favicon:**
- `priv/static/images/logo.svg`
- `priv/static/favicon.ico`
- `lib/web/components/layouts.ex` (logo reference)
- `lib/web/components/nav_drawer.ex` (logo reference)

**Task 8 — Landing & auth pages:**
- `lib/web/controllers/page_html/landing.html.heex`
- `lib/web/live/account_live/login.ex`
- `lib/web/live/account_live/confirmation.ex`
- `lib/web/live/account_live/settings.ex`
- `lib/web/live/account_live/registration.ex`

**Task 9 — Organization pages:**
- `lib/web/live/organization_live/index.html.heex`
- `lib/web/live/account_management_live/index.ex`
- `lib/web/live/account_management_live/show.ex`
- `lib/web/live/account_management_live/edit.ex`
- `lib/web/live/account_management_live/new.ex`

**Task 10 — Family pages:**
- `lib/web/live/family_live/index.html.heex`
- `lib/web/live/family_live/new.html.heex`
- `lib/web/live/family_live/show.html.heex`
- `lib/web/live/family_live/show.ex`
- `lib/web/live/family_live/graph_component.ex`
- `lib/web/live/family_live/tree_component.ex`
- `lib/web/live/family_live/side_panel_component.ex`
- `lib/web/live/family_live/people_list_component.ex`
- `lib/web/live/family_live/gallery_list_component.ex`
- `lib/web/live/family_live/vault_list_component.ex`
- `lib/web/live/family_live/person_selector_component.ex`
- `lib/web/live/family_live/print.html.heex` (no ds- tokens, but needs font updates for print)

**Task 11 — Person pages:**
- `lib/web/live/person_live/index.html.heex`
- `lib/web/live/person_live/new.html.heex`
- `lib/web/live/person_live/show.html.heex`
- `lib/web/live/person_live/show.ex`
- `lib/web/live/shared/person_form_component.html.heex`
- `lib/web/live/shared/add_relationship_component.ex`
- `lib/web/live/shared/quick_person_modal.ex`

**Task 12 — Gallery pages:**
- `lib/web/live/gallery_live/index.html.heex`
- `lib/web/live/gallery_live/show.html.heex`

**Task 13 — People index pages:**
- `lib/web/live/people_live/index.html.heex`
- `lib/web/live/org_people_live/index.html.heex`

**Task 14 — Kinship, birthday, memory, vault:**
- `lib/web/live/kinship_live.ex`
- `lib/web/live/kinship_live.html.heex`
- `lib/web/live/birthday_live/index.ex`
- `lib/web/live/memory_live/form.html.heex`
- `lib/web/live/memory_live/show.html.heex`
- `lib/web/live/vault_live/show.html.heex`
- `lib/web/live/comments/photo_comments_component.ex`
- `lib/ancestry/memories/content_renderer.ex`

**Task 15 — DESIGN.md update:**
- `DESIGN.md`

**Task 16 — Cleanup & precommit:**
- Remove old font files, daisyUI vendor file
- Run `mix precommit`

---

### Task 1: CSS Foundation — palette.css and app.css

**Files:**
- Create: `assets/css/palette.css`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Create `assets/css/palette.css`**

```css
/* Brutalist Design System — Color Palette & Utilities */
/* All project-specific variables and classes use the cm- prefix */

:root {
  /* Primary colors */
  --cm-indigo: #1E104E;
  --cm-plum: #452E5A;
  --cm-coral: #FF653F;
  --cm-golden: #FFC85C;
  --cm-black: #000000;
  --cm-white: #FFFFFF;

  /* Derived tones */
  --cm-surface: #FAFAFA;
  --cm-border: #E0E0E0;
  --cm-text-muted: #999999;
  --cm-coral-hover: #E8552F;
  --cm-indigo-hover: #150B3A;

  /* Semantic colors */
  --cm-error: #BA1A1A;
  --cm-success: #006D35;

  /* Semantic aliases */
  --cm-color-primary: var(--cm-coral);
  --cm-color-secondary: var(--cm-indigo);
  --cm-color-accent: var(--cm-golden);
  --cm-color-bg: var(--cm-white);
  --cm-color-surface: var(--cm-surface);
  --cm-color-text: var(--cm-black);
  --cm-color-text-muted: var(--cm-text-muted);
}

/* Utility classes for components that need more than a single Tailwind class */
.cm-tag {
  font-family: var(--cm-font-mono);
  font-size: 8px;
  font-weight: 700;
  padding: 2px 6px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  border-radius: 2px;
  display: inline-block;
}

.cm-tag-indigo {
  background-color: var(--cm-indigo);
  color: var(--cm-white);
}

.cm-tag-golden {
  background-color: var(--cm-golden);
  color: var(--cm-black);
}

.cm-stat {
  border: 1px solid var(--cm-border);
  border-top: 2px solid var(--cm-coral);
  border-radius: 2px;
  padding: 10px;
  text-align: center;
  background: var(--cm-white);
}

.cm-card {
  border: 2px solid var(--cm-black);
  border-radius: 2px;
  background: var(--cm-white);
  overflow: hidden;
}
```

- [ ] **Step 2: Rewrite `app.css` — remove daisyUI, old tokens, old fonts; add palette import and new theme**

Replace the full content of `assets/css/app.css`. The new file should:
1. Import `palette.css` first
2. Import Tailwind with the same `source(none)` and `@source` directives
3. Import heroicons plugin (keep), remove daisyUI plugin import
4. Import animate.css and trix.css (keep)
5. Add new `@font-face` declarations for Bebas Neue, Space Grotesk, Space Mono
6. Add new `@theme` block registering `cm-*` colors, `cm-font-*` families, `cm-radius` (2px)
7. Keep existing custom CSS rules (masonry, scrollbar hiding, trix editor, print, LiveView wrappers, tree drawer transitions)
8. Remove old shadow-ds-card and shadow-ds-ambient custom classes
9. Remove old `#people-table` zebra striping rule (uses `--color-base-200` daisyUI token) — replace with `--cm-surface`
10. Keep the PhoenixLiveView custom variants

Key `@theme` block content:
```css
@theme {
  --color-cm-indigo: var(--cm-indigo);
  --color-cm-plum: var(--cm-plum);
  --color-cm-coral: var(--cm-coral);
  --color-cm-golden: var(--cm-golden);
  --color-cm-black: var(--cm-black);
  --color-cm-white: var(--cm-white);
  --color-cm-surface: var(--cm-surface);
  --color-cm-border: var(--cm-border);
  --color-cm-text-muted: var(--cm-text-muted);
  --color-cm-coral-hover: var(--cm-coral-hover);
  --color-cm-indigo-hover: var(--cm-indigo-hover);
  --color-cm-error: var(--cm-error);
  --color-cm-success: var(--cm-success);

  --font-cm-display: 'Bebas Neue', sans-serif;
  --font-cm-body: 'Space Grotesk', sans-serif;
  --font-cm-mono: 'Space Mono', monospace;

  --radius-cm: 2px;
}
```

- [ ] **Step 3: Verify the app compiles and the dev server starts**

Run: `cd /Users/babbage/Work/ancestry && mix compile --warnings-as-errors`
Then start the dev server and verify no CSS build errors in the terminal.

- [ ] **Step 4: Commit**

```
git add assets/css/palette.css assets/css/app.css
git commit -m "Add brutalist palette.css and rewrite app.css theme"
```

---

### Task 2: Install New Font Files

**Files:**
- Create: `priv/static/fonts/bebas-neue.woff2`
- Create: `priv/static/fonts/space-grotesk-variable.woff2`
- Create: `priv/static/fonts/space-mono-regular.woff2`
- Create: `priv/static/fonts/space-mono-bold.woff2`

- [ ] **Step 1: Download font files from Google Fonts**

Download `.woff2` files to `priv/static/fonts/` using these commands:

```bash
# Bebas Neue (single weight 400)
curl -L "https://fonts.gstatic.com/s/bebasneue/v14/JTUSjIg69CK48gW7PXoo9Wlhyw.woff2" -o priv/static/fonts/bebas-neue.woff2

# Space Grotesk (variable, weights 300-700)
curl -L "https://fonts.gstatic.com/s/spacegrotesk/v16/V8mDoQDjQSkFtoMM3T6r8E7mPbF4Cw.woff2" -o priv/static/fonts/space-grotesk-variable.woff2

# Space Mono Regular (400)
curl -L "https://fonts.gstatic.com/s/spacemono/v13/i7dPIFZifjKcF5UAWdDRYEF8RQ.woff2" -o priv/static/fonts/space-mono-regular.woff2

# Space Mono Bold (700)
curl -L "https://fonts.gstatic.com/s/spacemono/v13/i7dMIFZifjKcF5UAWdDRaPpZYFKQHw.woff2" -o priv/static/fonts/space-mono-bold.woff2
```

If any of these URLs return 404 (Google occasionally rotates CDN paths), use the google-webfonts-helper site (https://gwfh.mranftl.com/fonts) to generate fresh download links for `woff2` format.

For Bebas Neue: single weight (400).
For Space Grotesk: variable font, weights 400-700.
For Space Mono: regular (400) and bold (700) as separate files.

- [ ] **Step 2: Verify fonts load in the browser**

Start dev server, open browser, inspect Network tab. Confirm all four font files load successfully with 200 status.

- [ ] **Step 3: Commit**

```
git add priv/static/fonts/bebas-neue.woff2 priv/static/fonts/space-grotesk-variable.woff2 priv/static/fonts/space-mono-regular.woff2 priv/static/fonts/space-mono-bold.woff2
git commit -m "Add Bebas Neue, Space Grotesk, Space Mono font files"
```

---

### Task 3: Global Token Migration

**Files:** All 46 files containing `ds-` tokens (see File Map above)

This task does a mechanical search-and-replace of the old design system tokens to the new `cm-*` equivalents. The visual design is NOT changed here — just the token names. This ensures nothing breaks before we start restyling.

- [ ] **Step 1: Create and run the token migration script**

Create a bash script at `scripts/migrate-tokens.sh` with the full set of sed replacements. Run it across all `.ex`, `.heex`, and `.css` files under `lib/` and `assets/css/`.

The mapping (old → new):

| Old Token | New Token |
|---|---|
| `bg-ds-surface` | `bg-cm-surface` |
| `bg-ds-surface-low` | `bg-cm-surface` |
| `bg-ds-surface-card` | `bg-cm-white` |
| `bg-ds-surface-high` | `bg-cm-surface` |
| `bg-ds-surface-highest` | `bg-cm-surface` |
| `bg-ds-surface-dim` | `bg-cm-border` |
| `bg-ds-primary` | `bg-cm-indigo` |
| `bg-ds-primary-container` | `bg-cm-indigo` |
| `bg-ds-on-primary` | `bg-cm-white` |
| `bg-ds-secondary` | `bg-cm-success` |
| `bg-ds-secondary-container` | `bg-cm-golden` |
| `bg-ds-tertiary` | `bg-cm-golden` |
| `bg-ds-error` | `bg-cm-error` |
| `text-ds-on-surface` | `text-cm-black` |
| `text-ds-on-surface-variant` | `text-cm-text-muted` |
| `text-ds-primary` | `text-cm-indigo` |
| `text-ds-on-primary` | `text-cm-white` |
| `text-ds-secondary` | `text-cm-success` |
| `text-ds-on-secondary-container` | `text-cm-indigo` |
| `text-ds-error` | `text-cm-error` |
| `text-ds-outline-variant` | `text-cm-text-muted` |
| `border-ds-primary` | `border-cm-indigo` |
| `border-ds-outline-variant` | `border-cm-border` |
| `ring-ds-primary` | `ring-cm-indigo` |
| `rounded-ds-sharp` | `rounded-cm` |
| `shadow-ds-card` | (remove entirely — delete class from element, keep element) |
| `shadow-ds-ambient` | (remove entirely — delete class from element, keep element) |
| `font-ds-heading` | `font-cm-display` |
| `font-ds-body` | `font-cm-body` |

**Note on `text-ds-on-secondary-container`:** This token was used as a foreground color on secondary surfaces (e.g., green text on light green badge). In the new palette, it maps to `text-cm-indigo` since indigo is the secondary color. Check actual usage in context and adjust if the semantic meaning differs.

The script should use `sed -i '' 's/old/new/g'` (macOS) with one replacement per line. For shadow removal, use a regex that matches `shadow-ds-card` and `shadow-ds-ambient` with optional trailing space and removes them.

```bash
#!/bin/bash
# Token migration script — run from project root
FILES=$(find lib/ assets/css/ -name "*.ex" -o -name "*.heex" -o -name "*.css" | grep -v "_build" | grep -v "deps")

for f in $FILES; do
  # ds-* token replacements (order matters: longer tokens first)
  sed -i '' \
    -e 's/bg-ds-surface-card/bg-cm-white/g' \
    -e 's/bg-ds-surface-highest/bg-cm-surface/g' \
    -e 's/bg-ds-surface-high/bg-cm-surface/g' \
    -e 's/bg-ds-surface-low/bg-cm-surface/g' \
    -e 's/bg-ds-surface-dim/bg-cm-border/g' \
    -e 's/bg-ds-surface/bg-cm-surface/g' \
    -e 's/bg-ds-primary-container/bg-cm-indigo/g' \
    -e 's/bg-ds-on-primary/bg-cm-white/g' \
    -e 's/bg-ds-primary/bg-cm-indigo/g' \
    -e 's/bg-ds-secondary-container/bg-cm-golden/g' \
    -e 's/bg-ds-secondary/bg-cm-success/g' \
    -e 's/bg-ds-tertiary/bg-cm-golden/g' \
    -e 's/bg-ds-error/bg-cm-error/g' \
    -e 's/text-ds-on-surface-variant/text-cm-text-muted/g' \
    -e 's/text-ds-on-surface/text-cm-black/g' \
    -e 's/text-ds-on-secondary-container/text-cm-indigo/g' \
    -e 's/text-ds-on-primary/text-cm-white/g' \
    -e 's/text-ds-primary/text-cm-indigo/g' \
    -e 's/text-ds-secondary/text-cm-success/g' \
    -e 's/text-ds-error/text-cm-error/g' \
    -e 's/text-ds-outline-variant/text-cm-text-muted/g' \
    -e 's/border-ds-outline-variant/border-cm-border/g' \
    -e 's/border-ds-primary/border-cm-indigo/g' \
    -e 's/ring-ds-primary/ring-cm-indigo/g' \
    -e 's/rounded-ds-sharp/rounded-cm/g' \
    -e 's/font-ds-heading/font-cm-display/g' \
    -e 's/font-ds-body/font-cm-body/g' \
    -e 's/ shadow-ds-card//g' \
    -e 's/shadow-ds-card //g' \
    -e 's/ shadow-ds-ambient//g' \
    -e 's/shadow-ds-ambient //g' \
    "$f"
done

echo "Token migration complete. Run: grep -r 'ds-' lib/ assets/css/ --include='*.ex' --include='*.heex' --include='*.css' to check for remaining references."
```

Also replace daisyUI color classes (these are safe to do mechanically):
| Old Class | New Equivalent |
|---|---|
| `bg-base-100` | `bg-cm-white` |
| `bg-base-200` | `bg-cm-surface` |
| `bg-base-300` | `bg-cm-border` |
| `border-base-200` | `border-cm-border` |
| `hover:bg-base-200` | `hover:bg-cm-surface` |
| `text-base-content` | `text-cm-black` |

Add these to the script as additional sed replacements.

**Do NOT replace these daisyUI classes mechanically** — they need manual, contextual replacement in Task 4:
- `btn`, `btn-primary`, `btn-soft` (structural component classes)
- `alert`, `alert-info`, `alert-error` (structural component classes)
- `toast`, `toast-top`, `toast-end` (structural component classes)
- `badge`, `badge-xs` (need context-specific replacement)

- [ ] **Step 2: Verify the app compiles**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Verify the dev server renders pages without errors**

Start `iex -S mix phx.server`, navigate to a few pages, check for no crashes.

- [ ] **Step 4: Commit**

```
git add -A
git commit -m "Migrate all ds-* tokens to cm-* equivalents"
```

---

### Task 4: Core Components — Buttons, Flash, Inputs

**Files:**
- Modify: `lib/web/components/core_components.ex`

- [ ] **Step 1: Replace flash/toast component**

Find the `flash` and `flash_group` function components. Replace daisyUI classes (`toast`, `toast-top`, `toast-end`, `alert`, `alert-info`, `alert-error`) with custom brutalist flash:

- Container: `fixed top-4 right-4 z-50 flex flex-col gap-2`
- Flash item: `border-l-[3px] rounded-cm px-4 py-3 font-cm-body text-sm text-cm-black shadow-md max-w-sm`
- Error variant: `border-l-cm-error bg-red-50`
- Info variant: `border-l-cm-indigo bg-indigo-50`
- Success variant: `border-l-cm-success bg-green-50`
- Close button: `font-cm-mono text-xs uppercase text-cm-text-muted`

- [ ] **Step 2: Replace button component**

Find the `button` function component. Replace daisyUI button classes (`btn`, `btn-primary`, `btn-soft`) with brutalist buttons:

- Primary: `bg-cm-coral text-cm-white font-cm-mono text-[10px] font-bold uppercase tracking-wider px-4 py-2 rounded-cm hover:bg-cm-coral-hover transition-colors`
- Secondary: `bg-cm-indigo text-cm-white font-cm-mono text-[10px] font-bold uppercase tracking-wider px-4 py-2 rounded-cm hover:bg-cm-indigo-hover transition-colors`

- [ ] **Step 3: Update input component default classes**

Update the `input` function component's default classes to use brutalist styling:
- Input: `border-2 border-cm-black rounded-cm font-cm-body text-sm px-3 py-2 focus:border-cm-coral focus:ring-0 focus:outline-none`
- Label: `font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-text-muted`

- [ ] **Step 4: Verify flash and button rendering**

Start dev server, trigger a flash message (e.g., login with wrong credentials), verify the new styling renders.

- [ ] **Step 5: Commit**

```
git add lib/web/components/core_components.ex
git commit -m "Replace daisyUI buttons and flash with brutalist components"
```

---

### Task 5: Layout, Mobile, Nav Components

**Files:**
- Modify: `lib/web/components/layouts.ex`
- Modify: `lib/web/components/mobile.ex`
- Modify: `lib/web/components/nav_drawer.ex`
- Modify: `lib/web/components/avatar_components.ex`
- Modify: `lib/web/components/layouts/root.html.heex`

- [ ] **Step 1: Update `layouts.ex` — header and toolbar**

The `.app` layout component should implement:

Header:
- `bg-cm-indigo border-b-[3px] border-cm-coral` 
- Logo: outlined white square `border-[2.5px] border-cm-white` with Bebas "A" `font-cm-display text-cm-white`
- "ANCESTRY" text: `font-cm-display text-cm-white tracking-[2px]`
- Desktop nav: `font-cm-mono text-[10px] uppercase tracking-wider text-cm-white/50` active: `text-cm-golden`
- Mobile: hamburger icon, hide nav links

Toolbar:
- `bg-cm-surface border-b border-cm-border`
- Breadcrumbs: `font-cm-mono text-[10px] text-cm-text-muted`

- [ ] **Step 2: Update `mobile.ex` — drawer, bottom sheet**

Update drawer and bottom_sheet components to use `cm-*` tokens:
- Drawer backdrop: `bg-cm-black/60`
- Drawer panel: `bg-cm-white border-l-2 border-cm-black`
- Bottom sheet: `bg-cm-white border-t-2 border-cm-black`
- Sheet actions: `font-cm-body`, danger state uses `text-cm-error`

- [ ] **Step 3: Update `nav_drawer.ex`**

- Background: `bg-cm-white`
- Logo: same outlined square as header
- Links: `font-cm-mono text-[10px] uppercase tracking-wider`
- Active link: `text-cm-coral`
- Sections: separated by `border-cm-border`

- [ ] **Step 4: Update `avatar_components.ex`**

Keep the 12-color avatar palette (it's functional, not decorative). Update fallback color and any `ds-*` references.

- [ ] **Step 5: Update `root.html.heex`**

- Set `<body>` default classes to `font-cm-body bg-cm-white text-cm-black`
- Update favicon reference if path changes

- [ ] **Step 6: Add mobile bottom navigation to the layout**

In `layouts.ex`, add a bottom nav bar visible only on mobile (`lg:hidden`):
- Container: `fixed bottom-0 left-0 right-0 bg-cm-white border-t border-cm-border z-40 flex`
- Items: `flex-1 text-center py-2 font-cm-mono text-[8px] uppercase tracking-wider text-cm-text-muted`
- Active item: `text-cm-coral`
- Icon containers: `w-5 h-5 mx-auto mb-1 border-[1.5px] border-current rounded-cm flex items-center justify-center text-[10px]`
- Active icon: `bg-cm-coral/10 border-cm-coral`
- Add `pb-16` padding to the main content area on mobile to prevent bottom nav overlap

Nav items and their routes (use `current_scope` to build org-scoped paths):
1. **Families** — `~p"/org/#{@current_scope.organization.id}"` — icon: `hero-home-solid` (5x5)
2. **People** — `~p"/org/#{@current_scope.organization.id}/people"` — icon: `hero-users-solid` (5x5)
3. **Galleries** — link to the first family's gallery or org root — icon: `hero-photo-solid` (5x5)
4. **More** — opens the nav drawer (phx-click to toggle) — icon: `hero-bars-3-solid` (5x5)

Highlight the active item based on the current `@active_tab` assign or by matching `@conn.request_path` / socket assigns.

- [ ] **Step 7: Verify layout renders correctly on desktop and mobile**

Check header, toolbar, nav drawer, bottom nav at different viewport widths.

- [ ] **Step 8: Commit**

```
git add lib/web/components/layouts.ex lib/web/components/mobile.ex lib/web/components/nav_drawer.ex lib/web/components/avatar_components.ex lib/web/components/layouts/root.html.heex
git commit -m "Update layout, mobile, and nav components to brutalist design"
```

---

### Task 6: Photo Gallery Component

**Files:**
- Modify: `lib/web/components/photo_gallery.ex`

- [ ] **Step 1: Update gallery grid**

- Grid gaps and padding: keep existing masonry structure
- Photo containers: `border-2 border-cm-black rounded-cm overflow-hidden` (replaces shadow-ds-card)
- Selection checkbox styling: use `cm-*` tokens

- [ ] **Step 2: Update lightbox**

The lightbox is a full-screen dark overlay — keep the dark background but update controls:
- Close/nav buttons: `font-cm-mono text-cm-white`
- Info panel: `bg-cm-indigo/95 text-cm-white font-cm-body`
- Photo counter: `font-cm-mono text-[10px]`

- [ ] **Step 3: Verify gallery and lightbox**

Navigate to a gallery, check grid rendering. Open lightbox, verify controls.

- [ ] **Step 4: Commit**

```
git add lib/web/components/photo_gallery.ex
git commit -m "Update photo gallery to brutalist design"
```

---

### Task 7: Logo & Favicon

**Files:**
- Replace: `priv/static/images/logo.svg`
- Replace: `priv/static/favicon.ico`

- [ ] **Step 1: Create new SVG logo**

Create an SVG with:
- Rectangle with 2.5px white stroke, no fill (outlined square)
- Bebas Neue "A" letter centered inside, white fill
- Viewbox sized appropriately (e.g., 36x36)
- The SVG should work on both indigo header background and standalone

- [ ] **Step 2: Create new favicon**

Create a favicon with:
- 32x32 and 16x16 sizes
- Indigo (`#1E104E`) background
- White outlined square with "A" letter
- Save as `favicon.ico` (multi-size ICO) or as a simple PNG favicon

- [ ] **Step 3: Delete old logo.png if no longer referenced**

Check if `logo.png` is referenced anywhere. If only `logo.svg` is used, delete the PNG.

- [ ] **Step 4: Verify logo and favicon in browser**

Check header logo renders, check browser tab favicon.

- [ ] **Step 5: Commit**

```
git add priv/static/images/logo.svg priv/static/favicon.ico
git commit -m "Replace logo and favicon with brutalist design"
```

---

### Task 8: Landing & Auth Pages

**Files:**
- Modify: `lib/web/controllers/page_html/landing.html.heex`
- Modify: `lib/web/live/account_live/login.ex`
- Modify: `lib/web/live/account_live/confirmation.ex`
- Modify: `lib/web/live/account_live/settings.ex`
- Modify: `lib/web/live/account_live/registration.ex`

- [ ] **Step 1: Restyle the landing page**

Apply brutalist typography and colors. Use `font-cm-display` for hero heading, `font-cm-body` for body text, `bg-cm-coral` for CTA button.

- [ ] **Step 2: Restyle login page**

- Form container: `cm-card` class (2px black border)
- Heading: `font-cm-display text-cm-indigo uppercase tracking-wider`
- Inputs: use the updated `<.input>` component (already restyled in Task 4)
- Submit button: primary brutalist button

- [ ] **Step 3: Restyle confirmation, settings, registration pages**

Same patterns as login — brutalist card containers, `cm-*` tokens throughout.

- [ ] **Step 4: Verify all auth pages render correctly**

Navigate to `/accounts/log-in`, `/accounts/settings`, `/accounts/confirm`. Check styling.

- [ ] **Step 5: Commit**

```
git add lib/web/controllers/page_html/landing.html.heex lib/web/live/account_live/
git commit -m "Restyle landing and auth pages to brutalist design"
```

---

### Task 9: Organization Pages

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex` (100 ds- tokens)
- Modify: `lib/web/live/account_management_live/index.ex` (42 ds- tokens)
- Modify: `lib/web/live/account_management_live/show.ex` (76 ds- tokens)
- Modify: `lib/web/live/account_management_live/edit.ex` (70 ds- tokens)
- Modify: `lib/web/live/account_management_live/new.ex` (31 ds- tokens)

- [ ] **Step 1: Restyle organization index**

- Organization cards: `cm-card` style with 2px black borders
- Stats: `cm-stat` style with coral top-accent
- Headings: `font-cm-display text-cm-indigo uppercase`
- Create org button: primary brutalist button

- [ ] **Step 2: Restyle account management pages**

Apply brutalist patterns to index, show, edit, new pages. Use card containers with black borders, mono labels, brutalist buttons.

- [ ] **Step 3: Verify organization pages**

Navigate to `/org`, click into an org. Check all four account management pages.

- [ ] **Step 4: Commit**

```
git add lib/web/live/organization_live/ lib/web/live/account_management_live/
git commit -m "Restyle organization and account management pages"
```

---

### Task 10: Family Pages

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex` (68 ds- tokens)
- Modify: `lib/web/live/family_live/new.html.heex` (34 ds- tokens)
- Modify: `lib/web/live/family_live/show.html.heex` (294 ds- tokens — largest file)
- Modify: `lib/web/live/family_live/show.ex` (10 ds- tokens)
- Modify: `lib/web/live/family_live/graph_component.ex` (35 ds- tokens)
- Modify: `lib/web/live/family_live/tree_component.ex` (47 ds- tokens)
- Modify: `lib/web/live/family_live/side_panel_component.ex` (13 ds- tokens)
- Modify: `lib/web/live/family_live/people_list_component.ex` (23 ds- tokens)
- Modify: `lib/web/live/family_live/gallery_list_component.ex` (10 ds- tokens)
- Modify: `lib/web/live/family_live/vault_list_component.ex` (11 ds- tokens)
- Modify: `lib/web/live/family_live/person_selector_component.ex` (21 ds- tokens)
- Modify: `lib/web/live/family_live/print.html.heex`

- [ ] **Step 1: Restyle family index**

Family cards: `cm-card` with plum photo area, brutalist tags, stats with coral accent.

- [ ] **Step 2: Restyle family new page**

Form in a `cm-card` container. Brutalist inputs and buttons.

- [ ] **Step 3: Restyle family show page (the biggest file — 294 tokens)**

This is the most complex page. Apply brutalist design to:
- Cover photo area (keep plum as fallback)
- Family info section
- Tab navigation (Graph/Tree/People/Galleries)
- All sub-sections

Read the file first, then systematically replace all tokens.

- [ ] **Step 4: Restyle graph_component and tree_component**

- Graph nodes: `cm-card` borders, `font-cm-body` for names, `font-cm-mono` for dates
- Tree indentation: keep structure, update colors to `cm-*`
- Focus state: `bg-cm-indigo text-cm-white` (replaces `bg-ds-primary-container`)

- [ ] **Step 5: Restyle side panel, people list, gallery list, vault list, person selector**

Apply brutalist tokens to all sub-components of the family show page.

- [ ] **Step 6: Update print template**

Update `print.html.heex` with new font families. Replace any hardcoded colors.

- [ ] **Step 7: Verify family pages**

Navigate through family index → new → show. Check graph view, tree view, side panel, galleries tab. Check print view.

- [ ] **Step 8: Commit**

```
git add lib/web/live/family_live/
git commit -m "Restyle family pages to brutalist design"
```

---

### Task 11: Person Pages

**Files:**
- Modify: `lib/web/live/person_live/index.html.heex` (5 ds- tokens)
- Modify: `lib/web/live/person_live/new.html.heex` (7 ds- tokens)
- Modify: `lib/web/live/person_live/show.html.heex` (191 ds- tokens)
- Modify: `lib/web/live/person_live/show.ex` (8 ds- tokens)
- Modify: `lib/web/live/shared/person_form_component.html.heex` (92 ds- tokens)
- Modify: `lib/web/live/shared/add_relationship_component.ex` (69 ds- tokens)
- Modify: `lib/web/live/shared/quick_person_modal.ex` (53 ds- tokens)

- [ ] **Step 1: Restyle person show page (191 tokens)**

- Hero photo area: keep overlay pattern, update to `cm-*` colors
- Info sections: brutalist cards, mono metadata
- Relationships section: `cm-card` borders
- Tagged photos grid: update borders and spacing

- [ ] **Step 2: Restyle person form component (92 tokens)**

Apply brutalist inputs, labels, and layout to the shared form.

- [ ] **Step 3: Restyle add_relationship_component and quick_person_modal**

- Modal/overlay: `bg-cm-black/60 backdrop-blur-sm`
- Modal panel: `bg-cm-white border-2 border-cm-black rounded-cm`
- Form elements: brutalist inputs and buttons

- [ ] **Step 4: Restyle person index and new pages**

Minor updates — these have few tokens.

- [ ] **Step 5: Verify person pages**

Navigate to person index → show → edit. Add a relationship. Check quick person modal.

- [ ] **Step 6: Commit**

```
git add lib/web/live/person_live/ lib/web/live/shared/
git commit -m "Restyle person pages and shared components"
```

---

### Task 12: Gallery Pages

**Files:**
- Modify: `lib/web/live/gallery_live/index.html.heex` (55 ds- tokens)
- Modify: `lib/web/live/gallery_live/show.html.heex` (98 ds- tokens)

- [ ] **Step 1: Restyle gallery index**

Gallery cards with brutalist borders, plum placeholder, mono metadata.

- [ ] **Step 2: Restyle gallery show**

- Upload area: `border-2 border-dashed border-cm-black rounded-cm`
- Photo grid: already updated in Task 6 (photo_gallery component)
- Gallery info: brutalist typography and spacing

- [ ] **Step 3: Verify gallery pages**

Navigate to gallery index → show. Upload a photo. Check grid rendering.

- [ ] **Step 4: Commit**

```
git add lib/web/live/gallery_live/
git commit -m "Restyle gallery pages to brutalist design"
```

---

### Task 13: People Index Pages

**Files:**
- Modify: `lib/web/live/people_live/index.html.heex` (94 ds- tokens)
- Modify: `lib/web/live/org_people_live/index.html.heex` (94 ds- tokens)

- [ ] **Step 1: Restyle family-scoped people index**

- People table/grid: `cm-card` borders on cards, `cm-*` colors
- Search input: brutalist input style
- Filters: `font-cm-mono` labels
- Replace `badge`/`badge-xs` daisyUI classes with `cm-tag` utility

- [ ] **Step 2: Restyle org-scoped people index**

Same patterns as family-scoped people index.

- [ ] **Step 3: Verify people pages**

Navigate to both people index pages. Search, filter, check card/table views.

- [ ] **Step 4: Commit**

```
git add lib/web/live/people_live/ lib/web/live/org_people_live/
git commit -m "Restyle people index pages to brutalist design"
```

---

### Task 14: Kinship, Birthday, Memory, Vault Pages

**Files:**
- Modify: `lib/web/live/kinship_live.ex` (26 ds- tokens)
- Modify: `lib/web/live/kinship_live.html.heex` (29 ds- tokens)
- Modify: `lib/web/live/birthday_live/index.ex` (22 ds- tokens)
- Modify: `lib/web/live/memory_live/form.html.heex` (78 ds- tokens)
- Modify: `lib/web/live/memory_live/show.html.heex` (12 ds- tokens)
- Modify: `lib/web/live/vault_live/show.html.heex` (82 ds- tokens)
- Modify: `lib/web/live/comments/photo_comments_component.ex` (5 ds- tokens)
- Modify: `lib/ancestry/memories/content_renderer.ex` (6 ds- tokens)

- [ ] **Step 1: Restyle kinship calculator**

Replace all `base-100`/`base-200`/`base-300` daisyUI references. Apply brutalist styling:
- Person selector dropdowns: brutalist inputs
- Result cards: `cm-card` borders
- Path visualization: `cm-*` colors

- [ ] **Step 2: Restyle birthday page**

- Month headers: `font-cm-display text-cm-indigo uppercase`
- Person cards: brutalist cards with mono dates
- Today marker: `border-cm-coral` (replaces `#006d35`)

- [ ] **Step 3: Restyle memory form and show pages**

Apply brutalist tokens to the Trix editor container, memory cards, and vault show page.

- [ ] **Step 4: Restyle vault show page**

Brutalist cards, mono metadata, `cm-*` tokens throughout.

- [ ] **Step 5: Update photo comments component and content renderer**

Minor token updates in these small files.

- [ ] **Step 6: Verify all pages**

Navigate to kinship calculator, birthday view, memory form, vault show, photo comments.

- [ ] **Step 7: Commit**

```
git add lib/web/live/kinship_live.ex lib/web/live/kinship_live.html.heex lib/web/live/birthday_live/ lib/web/live/memory_live/ lib/web/live/vault_live/ lib/web/live/comments/ lib/ancestry/memories/content_renderer.ex
git commit -m "Restyle kinship, birthday, memory, and vault pages"
```

---

### Task 15: Update DESIGN.md

**Files:**
- Modify: `DESIGN.md`

- [ ] **Step 1: Replace the Visual system section**

Use the replacement text from the design spec (`docs/plans/2026-04-25-brutalist-design-system-design.md`, "DESIGN.md Updates" section). Replace the current color palette, surface hierarchy, and signal color documentation with the new `cm-*` palette table.

- [ ] **Step 2: Replace the Typography section**

Update from Manrope/Inter to Bebas Neue/Space Grotesk/Space Mono with the three-font-three-role system.

- [ ] **Step 3: Update component guidance**

Update buttons, cards, inputs sections to reference brutalist patterns (black borders, flat fills, no shadows, Space Mono uppercase for actions).

- [ ] **Step 4: Commit**

```
git add DESIGN.md
git commit -m "Update DESIGN.md with brutalist design system"
```

---

### Task 16: Cleanup & Final Verification

**Files:**
- Delete: `assets/vendor/daisyui.js`
- Delete: `priv/static/fonts/manrope-variable.woff2`
- Delete: `priv/static/fonts/inter-variable.woff2`
- Delete: `priv/static/images/logo.png` (if no longer referenced)

- [ ] **Step 1: Delete old files**

Remove daisyUI vendor file and old font files.

- [ ] **Step 2: Search for any remaining `ds-` references**

Run: `grep -r "ds-" lib/ assets/css/ --include="*.ex" --include="*.heex" --include="*.css"`

Fix any remaining references.

- [ ] **Step 3: Search for any remaining daisyUI references**

Run: `grep -r "daisyui\|base-100\|base-200\|base-300\|btn-primary\|btn-soft\|alert-info\|alert-error\|toast-top\|badge-xs" lib/ assets/ --include="*.ex" --include="*.heex" --include="*.css" --include="*.js"`

Fix any remaining references.

- [ ] **Step 4: Run `mix precommit`**

This runs compile (warnings-as-errors), removes unused deps, formats, and runs tests.

Fix any issues.

- [ ] **Step 5: Visual smoke test**

Start `iex -S mix phx.server` and navigate through all major pages:
1. Landing page (`/`)
2. Login (`/accounts/log-in`)
3. Org index (`/org`)
4. Family index, show, new
5. Person show
6. Gallery show
7. People index (family-scoped and org-scoped)
8. Kinship calculator
9. Birthday view
10. Memory/vault pages

Check both desktop and mobile viewport widths.

- [ ] **Step 6: Commit cleanup**

```
git add -A
git commit -m "Remove old fonts, daisyUI, and remaining ds-* references"
```
