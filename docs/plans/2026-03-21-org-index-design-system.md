# Org Index Design System Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the "Precision Authority" CSS design system foundation using Tailwind v4 `@theme` tokens and apply it to the org index page as the first consumer.

**Architecture:** Self-hosted variable fonts (Manrope, Inter) loaded via `@font-face`, `ds-`-namespaced color/font/radius tokens registered in `@theme`, custom ambient shadow utility. DaisyUI remains loaded alongside for other pages. Org index template rewritten to use new tokens exclusively.

**Tech Stack:** Tailwind CSS v4, Phoenix LiveView, HEEx templates

**Spec:** `docs/superpowers/specs/2026-03-21-org-index-design-system-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `priv/static/fonts/manrope-variable.woff2` | Manrope variable font file |
| Create | `priv/static/fonts/inter-variable.woff2` | Inter variable font file |
| Modify | `assets/css/app.css` | `@font-face`, `@theme` tokens, `shadow-ds-ambient`, daisyUI dark theme disable |
| Modify | `lib/web/live/organization_live/index.html.heex` | Template rewrite using ds- tokens |

---

### Task 1: Download and install self-hosted font files

**Files:**
- Create: `priv/static/fonts/manrope-variable.woff2`
- Create: `priv/static/fonts/inter-variable.woff2`

The `"fonts"` path is already included in `static_paths` (`lib/web.ex:20`), so these will be served automatically at `/fonts/`.

- [ ] **Step 1: Create the fonts directory**

```bash
mkdir -p priv/static/fonts
```

- [ ] **Step 2: Download Manrope variable font**

Download from Google Fonts' GitHub repo (the canonical source for variable WOFF2 files):

```bash
curl -L -o priv/static/fonts/manrope-variable.woff2 \
  "https://github.com/nicholasgasior/manrope-variable/raw/main/fonts/woff2/Manrope%5Bwght%5D.woff2"
```

If that URL is unavailable, download from Google Fonts directly:
1. Visit fonts.google.com/specimen/Manrope
2. Download the font family ZIP
3. Extract the `.woff2` variable file (or convert `.ttf` to `.woff2` using `woff2_compress`)
4. Save as `priv/static/fonts/manrope-variable.woff2`

- [ ] **Step 3: Download Inter variable font**

```bash
curl -L -o priv/static/fonts/inter-variable.woff2 \
  "https://github.com/rsms/inter/raw/master/docs/font-files/InterVariable.woff2"
```

If that URL is unavailable, download from https://rsms.me/inter/ — Inter's official site. Save the variable WOFF2 file as `priv/static/fonts/inter-variable.woff2`.

- [ ] **Step 4: Verify files exist and have reasonable sizes**

```bash
ls -la priv/static/fonts/
```

Expected: Two `.woff2` files, each roughly 50-150KB.

- [ ] **Step 5: Verify fonts are served by the dev server**

```bash
# Start the server (if not already running)
# Then check the font is accessible:
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/fonts/manrope-variable.woff2
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/fonts/inter-variable.woff2
```

Expected: `200` for both.

- [ ] **Step 6: Commit**

```bash
git add priv/static/fonts/
git commit -m "Add self-hosted Manrope and Inter variable font files"
```

---

### Task 2: Add CSS foundation — @font-face, @theme tokens, shadow utility, disable dark theme

**Files:**
- Modify: `assets/css/app.css`

Reference the current file structure (`assets/css/app.css`):
- Lines 1-7: Tailwind import, `@source`, heroicons plugin
- Lines 16-18: daisyUI plugin with `themes: light --default, dark --prefersdark`
- Lines 20+: animate.css import, custom variants, custom CSS rules

All new CSS goes after the existing imports/plugins but before the custom CSS rules section.

- [ ] **Step 1: Add `@font-face` declarations**

Insert after the `@import "../vendor/animate.css";` line (line 20). This is the first of three blocks to insert in sequence (`@font-face` → `@theme` → shadow utility), all before the `/* Add variants */` comment (line 22):

```css
/* === Design System: Font Loading === */
@font-face {
  font-family: 'Manrope';
  src: url('/fonts/manrope-variable.woff2') format('woff2');
  font-weight: 700 800;
  font-display: swap;
}

@font-face {
  font-family: 'Inter';
  src: url('/fonts/inter-variable.woff2') format('woff2');
  font-weight: 400 700;
  font-display: swap;
}
```

- [ ] **Step 2: Add `@theme` block with ds-namespaced tokens**

Insert immediately after the `@font-face` blocks you just added:

```css
/* === Design System: Theme Tokens (Precision Authority) === */
@theme {
  /* Surface Hierarchy (Tonal Layering) */
  --color-ds-surface: #f8f9ff;
  --color-ds-surface-low: #eff4ff;
  --color-ds-surface-card: #ffffff;
  --color-ds-surface-high: #dce9ff;
  --color-ds-surface-highest: #d3e4fe;
  --color-ds-surface-dim: #cbdbf5;

  /* Text / On-Surface */
  --color-ds-on-surface: #0b1c30;
  --color-ds-on-surface-variant: #444748;
  --color-ds-outline-variant: #c4c7c7;

  /* Signal Colors (functional only) */
  --color-ds-primary: #000000;
  --color-ds-primary-container: #1c1b1b;
  --color-ds-on-primary: #ffffff;
  --color-ds-secondary: #006d35;
  --color-ds-secondary-container: #8df9a8;
  --color-ds-on-secondary-container: #007439;
  --color-ds-tertiary: #ffb77d;
  --color-ds-error: #ba1a1a;

  /* Typography */
  --font-ds-heading: 'Manrope', sans-serif;
  --font-ds-body: 'Inter', sans-serif;

  /* Radius (Brutalist) */
  --radius-ds-sharp: 0.125rem;
}
```

- [ ] **Step 3: Add ambient shadow utility**

Insert immediately after the `@theme` block you just added:

```css
/* === Design System: Ambient Shadow === */
.shadow-ds-ambient {
  box-shadow: 0 8px 32px rgba(11, 28, 48, 0.06);
}
```

- [ ] **Step 4: Disable daisyUI dark theme**

Change line 17 inside the daisyUI `@plugin` block (lines 16-18) in `assets/css/app.css` from:

```css
@plugin "../vendor/daisyui" {
  themes: light --default, dark --prefersdark;
}
```

to:

```css
@plugin "../vendor/daisyui" {
  themes: light --default;
}
```

- [ ] **Step 5: Verify the app compiles and other pages still work**

```bash
mix assets.build
```

Expected: No errors. The build should complete successfully since all new tokens use the `ds-` namespace and don't collide with daisyUI.

- [ ] **Step 6: Verify tokens generate Tailwind utilities**

Start the dev server and check that the new utility classes are available by inspecting the generated CSS:

```bash
grep -c "ds-surface" priv/static/assets/app.css
```

Expected: Multiple matches. At this stage, you are verifying the CSS custom property declarations from `@theme` exist (e.g., `--color-ds-surface`). The utility classes (e.g., `bg-ds-surface`) will only appear after Task 3 when the template uses them.

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css
git commit -m "Add Precision Authority design system tokens via Tailwind v4 @theme"
```

---

### Task 3: Rewrite org index page template — toolbar and card grid

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`

This task rewrites the toolbar and card grid sections. The modal is handled in Task 4.

**Important:** The template must remain wrapped in `<Layouts.app flash={@flash}>...</Layouts.app>`. Only replace the content between these wrapper tags. Do NOT remove the `<Layouts.app>` opening (line 1) or closing (line 77) tags.

Preserved test IDs: `org-new-btn`, `org-create-modal`, `org-create-form`, `org-create-submit-btn`, `org-create-backdrop`. New test ID added: `org-create-cancel-btn`.

- [ ] **Step 1: Rewrite the toolbar section**

Replace lines 2-13 of `index.html.heex` (the `<:toolbar>` slot) with:

```heex
<:toolbar>
  <div class="max-w-7xl mx-auto flex items-center justify-between py-4 px-4 sm:px-6 lg:px-8">
    <h1 class="text-2xl font-ds-heading font-extrabold tracking-tight text-ds-on-surface">
      Organizations
    </h1>
    <button
      phx-click="new_organization"
      class="inline-flex items-center gap-2 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-5 py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
      {test_id("org-new-btn")}
    >
      <.icon name="hero-plus" class="w-4 h-4" /> New Organization
    </button>
  </div>
</:toolbar>
```

- [ ] **Step 2: Rewrite the card grid section**

Replace everything between the closing `</:toolbar>` tag and the `<%= if @show_create_modal do %>` line (lines 15-36 in the current file). Note: this adds a new outer `<div class="bg-ds-surface-low">` wrapper that does not exist in the current template — this is intentional to create the tonal background shift. Replace with:

```heex
<div class="bg-ds-surface-low min-h-screen">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div
      id="organizations"
      phx-update="stream"
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5"
    >
      <div
        id="organizations-empty"
        class="hidden only:flex flex-col items-center justify-center py-24 col-span-full bg-ds-surface-dim rounded-ds-sharp"
      >
        <p class="text-lg font-ds-heading font-bold text-ds-on-surface">No organizations yet</p>
      </div>
      <.link
        :for={{id, org} <- @streams.organizations}
        id={id}
        navigate={~p"/org/#{org.id}"}
        class="block bg-ds-surface-card rounded-ds-sharp p-6 hover:bg-ds-surface-highest transition-colors"
      >
        <h2 class="text-base font-ds-heading font-bold text-ds-on-surface tracking-tight">{org.name}</h2>
      </.link>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile --warnings-as-errors
```

Expected: No errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/organization_live/index.html.heex
git commit -m "Rewrite org index toolbar and card grid with design system tokens"
```

---

### Task 4: Rewrite org index page template — create modal

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`

This task rewrites the create organization modal with glassmorphism styling, ARIA attributes, escape key handling, and focus management.

- [ ] **Step 1: Rewrite the modal section**

Replace the entire `<%= if @show_create_modal do %>` block (from `<%= if @show_create_modal do %>` through the matching `<% end %>`) with:

```heex
<%= if @show_create_modal do %>
  <div
    id="create-org-overlay"
    class="fixed inset-0 z-50 flex items-center justify-center"
    phx-window-keydown="cancel_create"
    phx-key="Escape"
    phx-mounted={JS.focus_first()}
  >
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="cancel_create"
      {test_id("org-create-backdrop")}
    >
    </div>
    <div
      id="create-organization-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="create-org-title"
      class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient rounded-ds-sharp w-full max-w-md mx-4 p-8"
      {test_id("org-create-modal")}
    >
      <h2 id="create-org-title" class="text-xl font-ds-heading font-bold text-ds-on-surface mb-6">
        New Organization
      </h2>
      <.form
        for={@form}
        id="create-organization-form"
        phx-change="validate"
        phx-submit="save"
        {test_id("org-create-form")}
      >
        <.input field={@form[:name]} label="Organization name" autofocus />
        <div class="flex gap-3 mt-6">
          <button
            type="submit"
            class="flex-1 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
            phx-disable-with="Creating..."
            {test_id("org-create-submit-btn")}
          >
            Create
          </button>
          <button
            type="button"
            phx-click="cancel_create"
            class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
            {test_id("org-create-cancel-btn")}
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
  </div>
<% end %>
```

- [ ] **Step 2: Verify `JS` module is available**

Check that the LiveView module has access to `Phoenix.LiveView.JS`. It should already be available via `use Web, :live_view`. Verify:

```bash
grep -n "JS\." lib/web/live/organization_live/index.html.heex
```

Expected: The `JS.focus_first()` call on the `phx-mounted` attribute.

- [ ] **Step 3: Verify compilation**

```bash
mix compile --warnings-as-errors
```

Expected: No errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/organization_live/index.html.heex
git commit -m "Rewrite org index modal with glassmorphism and accessibility improvements"
```

---

### Task 5: Run existing tests and verify nothing is broken

**Files:**
- No files modified — verification only

The existing E2E tests in `test/user_flows/create_organization_test.exs` exercise all org index interactions (create, cancel, backdrop dismiss, form reset). All `test_id` selectors were preserved, so these should pass unchanged.

- [ ] **Step 1: Run the org-specific E2E tests**

```bash
mix test test/user_flows/create_organization_test.exs
```

Expected: All tests pass (currently 4 tests).

- [ ] **Step 2: Run the full test suite**

```bash
mix test
```

Expected: All tests pass. No regressions from the CSS changes or template rewrite.

- [ ] **Step 3: Run the precommit check**

```bash
mix precommit
```

Expected: Compilation (warnings-as-errors), unused deps check, format check, and tests all pass.

---

### Task 6: Final visual verification and cleanup

**Files:**
- No files modified — manual verification

- [ ] **Step 1: Start the dev server and visually verify the org index page**

```bash
iex -S mix phx.server
```

Open `http://localhost:4000` in a browser. Verify:
- Page background is `#f8f9ff` (cool light blue-white)
- Toolbar has Manrope heading, black gradient "New Organization" button with 2px radius
- Cards have white background on the `#eff4ff` surface, no borders, no shadows
- Cards change to `#d3e4fe` on hover
- Empty state (if no orgs) shows `#cbdbf5` background
- Clicking "New Organization" opens a glassmorphic modal with backdrop blur

- [ ] **Step 2: Verify other pages are unaffected**

Navigate to an existing family page (e.g., `/org/{id}`). Verify:
- The family index page still uses daisyUI styling
- Buttons, cards, modals look the same as before
- No visual regressions

- [ ] **Step 3: Verify the modal glassmorphism effect**

With the "New Organization" modal open:
- The backdrop should have 60% black with blur
- The modal itself should be 80% opaque white with 20px blur behind it
- The ambient shadow should be visible but subtle

- [ ] **Step 4: Commit any formatting changes if needed**

```bash
mix format
git status
```

If there are formatting changes, stage only the relevant files:

```bash
git add assets/css/app.css lib/web/live/organization_live/index.html.heex
git commit -m "Format code after design system migration"
```
