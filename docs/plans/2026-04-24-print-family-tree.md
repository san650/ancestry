# Print Family Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the family tree page print-friendly — Cmd+P hides all chrome and shows only the family name heading and text-only person cards with SVG connectors.

**Architecture:** Pure CSS `@media print` rules in `app.css` plus a print-only `<h1>` in `show.html.heex`. No server-side changes, no JS changes, no new routes.

**Tech Stack:** Tailwind CSS v4, `@media print`, Phoenix LiveView templates

**Spec:** `docs/plans/2026-04-24-print-family-tree-design.md`

---

### Task 1: Add print-only family name heading

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex:186` (above the tree canvas grid)

- [ ] **Step 1: Add the print-only `<h1>` above the tree canvas grid**

Insert a heading right before the `grid` div (line 186). It must be hidden on screen and visible only in print:

```heex
  <%!-- Print-only family name heading --%>
  <h1 class="hidden print:block text-2xl font-ds-heading font-bold text-black text-center mb-4">
    {@family.name}
  </h1>
```

Insert this between line 184 (`</.nav_drawer>`) and line 186 (`<div class="grid grid-cols-1 ...`).

- [ ] **Step 2: Verify the template compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no warnings

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/show.html.heex
git commit -m "Add print-only family name heading to family tree page"
```

---

### Task 2: Add `@media print` CSS rules

**Files:**
- Modify: `assets/css/app.css` (append at end of file, after the tree drawer transitions block at line ~143)

- [ ] **Step 1: Add the `@media print` block**

Append the following to the end of `assets/css/app.css`:

```css
/* === Print-friendly family tree ===
   Hides all chrome; shows only the family name heading and
   text-only person cards with SVG connectors.
   Triggered by the browser's native Cmd+P / Ctrl+P.        */
@media print {
  @page {
    size: landscape;
    margin: 1cm;
  }

  /* Force clean white background */
  body,
  [data-phx-main] {
    background: white !important;
  }

  /* ---- Hide application chrome ---- */

  /* App header (logo, nav links, account) */
  header {
    display: none !important;
  }

  /* Toolbar (breadcrumb bar, action buttons) */
  #toolbar {
    display: none !important;
  }

  /* Nav drawer (mobile) + backdrop */
  #nav-drawer,
  #nav-drawer-backdrop {
    display: none !important;
  }

  /* Side panel (desktop) */
  #side-panel-desktop {
    display: none !important;
  }

  /* Tree depth drawer (desktop) */
  #tree-drawer {
    display: none !important;
  }

  /* Mobile tree depth sheet */
  [data-testid="mobile-tree-sheet"] {
    display: none !important;
  }

  /* All modals (fixed overlays) */
  .fixed.inset-0.z-50 {
    display: none !important;
  }

  /* Flash messages */
  #flash-group {
    display: none !important;
  }

  /* ---- Tree canvas: remove scroll constraint ---- */

  #tree-canvas {
    overflow: visible !important;
    padding: 0 !important;
  }

  /* Remove the outer grid layout (tree + side panel) */
  #tree-canvas {
    order: unset !important;
  }

  /* ---- Person cards: text-only, compact ---- */

  /* Hide all photos and placeholder icons inside person cards */
  #graph-canvas img,
  #graph-canvas .hero-user {
    display: none !important;
  }

  /* Hide the mobile photo+overlay card (the entire mobile div) */
  #graph-canvas .lg\:hidden {
    display: none !important;
  }

  /* Force the desktop card layout to always show (even on mobile-sized paper) */
  #graph-canvas .hidden.lg\:flex {
    display: flex !important;
  }

  /* Hide "has more" chevron pills */
  #graph-canvas [title*="Has more"] {
    display: none !important;
  }

  /* Hide person navigation arrows */
  #graph-canvas a[aria-label] {
    display: none !important;
  }

  /* Strip interactive styling from person cards */
  #graph-canvas button {
    cursor: default !important;
    box-shadow: none !important;
    border-color: #c4c7c7 !important;
    background: white !important;
    color: black !important;
  }

  /* Ensure name text is always black */
  #graph-canvas button p {
    color: black !important;
  }

  /* Ensure date text is always dark gray */
  #graph-canvas button p:last-child {
    color: #444748 !important;
  }

  /* SVG connectors — ensure they print */
  #graph-connector-svg {
    print-color-adjust: exact;
    -webkit-print-color-adjust: exact;
  }
}
```

- [ ] **Step 2: Verify the app compiles and CSS is valid**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no warnings (CSS is bundled by esbuild, compilation catches syntax errors)

- [ ] **Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "Add @media print rules for family tree page"
```

---

### Task 3: Add CLAUDE.md for family_live directory

**Files:**
- Create: `lib/web/live/family_live/CLAUDE.md`

- [ ] **Step 1: Create the CLAUDE.md file**

```markdown
# Family Live

## Print-friendly tree view

The family show page (`show.html.heex`) is print-friendly. When users print with Cmd+P / Ctrl+P, CSS `@media print` rules in `assets/css/app.css` hide all application chrome and display only the family name and text-only person cards with SVG connectors.

**When adding new features to the family show page**, ensure they are hidden from print output. Use `print:hidden` (Tailwind) on new elements, or add a `display: none !important` rule in the `@media print` block in `app.css`. Only elements that are part of the printed tree (family name, person cards, connector lines) should be visible in print.
```

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/family_live/CLAUDE.md
git commit -m "Add CLAUDE.md documenting print-friendly tree view"
```

---

### Task 4: Manual verification

- [ ] **Step 1: Start the dev server**

Run: `iex -S mix phx.server`

- [ ] **Step 2: Navigate to a family tree page and trigger print preview**

1. Open `http://localhost:4000` in browser
2. Log in and navigate to a family with a tree
3. Press Cmd+P (or Ctrl+P) to open print preview
4. Verify:
   - Family name appears at the top
   - All person cards show names and dates only (no photos)
   - SVG connector lines are visible
   - No header, toolbar, side panel, drawer, or modals appear
   - Page orientation is landscape

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: all checks pass (compile, format, tests)
