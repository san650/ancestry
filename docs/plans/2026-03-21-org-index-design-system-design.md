# Design Spec: Org Index Page — Design System Foundation

## Summary

Establish the CSS foundation implementing the "Precision Authority" design system (DESIGN.md) using Tailwind v4's `@theme` directive, then apply it to the org index page (`OrganizationLive.Index`) as the first consumer. DaisyUI remains loaded during a parallel deprecation period so other pages continue to function.

## Decisions

- **Remove daisyUI:** Yes, but staged. DaisyUI stays loaded alongside the new tokens during a parallel period. Each page migrates individually; daisyUI is removed once all pages are converted.
- **Dark mode:** Light-only for now. Disable daisyUI's `dark --prefersdark` theme to prevent conflicts (change to `themes: light --default` in `app.css`).
- **CSS approach:** Tailwind v4 `@theme` directive registers DESIGN.md tokens as first-class utilities.
- **Token namespacing:** All design system tokens use a `ds-` prefix (e.g., `bg-ds-primary`, `text-ds-on-surface`) to avoid collisions with daisyUI's `--color-primary`, `--color-secondary`, `--color-error`. DaisyUI pages continue to work unchanged.
- **Font hosting:** Self-host Manrope and Inter WOFF2 files in `priv/static/fonts/` (already in `static_paths`) to follow the project's vendoring convention and avoid CDN/GDPR concerns.
- **Layout compatibility:** No changes to `layouts.ex` in this effort. The org index page is self-contained via its toolbar slot and content wrapper.

## Token Name Mapping

DESIGN.md names → CSS token names → Tailwind utility names:

| DESIGN.md Name | CSS Token | Tailwind Class |
|---|---|---|
| `surface` / background | `--color-ds-surface` | `bg-ds-surface` |
| `surface-container-low` | `--color-ds-surface-low` | `bg-ds-surface-low` |
| `surface-container-lowest` | `--color-ds-surface-card` | `bg-ds-surface-card` |
| `surface-container-high` | `--color-ds-surface-high` | `bg-ds-surface-high` |
| `surface-container-highest` | `--color-ds-surface-highest` | `bg-ds-surface-highest` |
| `surface-dim` | `--color-ds-surface-dim` | `bg-ds-surface-dim` |
| `on-surface` | `--color-ds-on-surface` | `text-ds-on-surface` |
| `on_surface_variant` | `--color-ds-on-surface-variant` | `text-ds-on-surface-variant` |
| `outline-variant` | `--color-ds-outline-variant` | `border-ds-outline-variant` |
| `primary` | `--color-ds-primary` | `bg-ds-primary` |
| `primary_container` | `--color-ds-primary-container` | `to-ds-primary-container` |
| `on-primary` (white) | `--color-ds-on-primary` | `text-ds-on-primary` |
| `secondary` (success) | `--color-ds-secondary` | `bg-ds-secondary` |
| `secondary_container` | `--color-ds-secondary-container` | `bg-ds-secondary-container` |
| `on_secondary_container` | `--color-ds-on-secondary-container` | `text-ds-on-secondary-container` |
| `tertiary` (warning) | `--color-ds-tertiary` | `bg-ds-tertiary` |
| `error` | `--color-ds-error` | `text-ds-error` |

## Part 1: CSS Foundation

### Font Loading

Self-host font files. Download Manrope (700, 800 weights) and Inter (400, 500, 600, 700 weights) variable WOFF2 files into `priv/static/fonts/` (the `"fonts"` path is already included in `static_paths`).

Add declarations in `app.css` in this order: `@font-face` first, then `@theme`, then custom utilities. The `@font-face` blocks go after the Tailwind import but before `@theme`:

```css
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

Variable font files keep it to 2 files total (~200KB combined).

### Theme Tokens

Add a `@theme` block in `app.css` (after the Tailwind import) with `ds-` namespaced tokens:

```css
@theme {
  /* === Surface Hierarchy (Tonal Layering) === */
  --color-ds-surface: #f8f9ff;              /* Level 0 — page background */
  --color-ds-surface-low: #eff4ff;          /* Level 1 — sidebars, toolbars */
  --color-ds-surface-card: #ffffff;         /* Level 2 — interactive cards */
  --color-ds-surface-high: #dce9ff;         /* secondary button backgrounds */
  --color-ds-surface-highest: #d3e4fe;      /* hover/active state */
  --color-ds-surface-dim: #cbdbf5;          /* empty states */

  /* === Text / On-Surface === */
  --color-ds-on-surface: #0b1c30;           /* primary text */
  --color-ds-on-surface-variant: #444748;   /* secondary labels */
  --color-ds-outline-variant: #c4c7c7;      /* ghost borders (use at 20% opacity) */

  /* === Signal Colors (functional only) === */
  --color-ds-primary: #000000;
  --color-ds-primary-container: #1c1b1b;
  --color-ds-on-primary: #ffffff;
  --color-ds-secondary: #006d35;            /* success only */
  --color-ds-secondary-container: #8df9a8;
  --color-ds-on-secondary-container: #007439;
  --color-ds-tertiary: #ffb77d;             /* warning only */
  --color-ds-error: #ba1a1a;

  /* === Typography === */
  --font-ds-heading: 'Manrope', sans-serif;
  --font-ds-body: 'Inter', sans-serif;

  /* === Radius (Brutalist) === */
  --radius-ds-sharp: 0.125rem;              /* 2px — the only radius */
}
```

Generated utilities: `bg-ds-surface`, `bg-ds-surface-low`, `bg-ds-surface-card`, `text-ds-on-surface`, `font-ds-heading`, `font-ds-body`, `rounded-ds-sharp`, etc.

### Ambient Shadow Utility

Add a custom CSS rule for the tinted ambient shadow used on floating elements (modals, dropdowns):

```css
.shadow-ds-ambient {
  box-shadow: 0 8px 32px rgba(11, 28, 48, 0.06);
}
```

### DaisyUI Dark Theme

Change the daisyUI plugin config in `app.css` from:

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

This prevents daisyUI dark mode from conflicting with the light-only design system tokens.

## Part 2: Org Index Page Template

### Toolbar

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

- Manrope (`font-ds-heading`) for title, Inter (`font-ds-body`) for button
- Black gradient CTA per "Signature Textures" rule
- `rounded-ds-sharp` (2px)

### Card Grid

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

- No borders, no shadows — tonal lift only (`bg-ds-surface-card` on `bg-ds-surface-low`)
- Hover: `bg-ds-surface-highest` (`#d3e4fe`)
- Empty state: `bg-ds-surface-dim` hollowed-out well
- `rounded-ds-sharp` everywhere

### Create Modal (Glassmorphism)

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

- Glassmorphism: `bg-ds-surface-card/80 backdrop-blur-[20px]`
- Ambient shadow: `shadow-ds-ambient` (custom class)
- Primary CTA: black gradient; Secondary: `bg-ds-surface-high` (per DESIGN.md component spec)
- Escape key closes modal via `phx-window-keydown`
- Focus management: `phx-mounted={JS.focus_first()}` moves focus into the modal on open
- ARIA: `role="dialog"`, `aria-modal="true"`, `aria-labelledby`
- Cancel button has `test_id`
- No entry/exit animation for now (deferred — acceptable during foundation work)

## Known Tradeoffs

These are accepted visual inconsistencies during the parallel deprecation period:

1. **Toolbar border:** The toolbar wrapper in `layouts.ex` renders `border-b border-base-200` (a 1px bottom border) which violates the design system's No-Line Rule. This will be fixed when `layouts.ex` is migrated.
2. **Navbar styling:** The navbar uses daisyUI's `navbar` class and system fonts, creating a visible style discontinuity above the org index content. This will be fixed when `layouts.ex` is migrated.
3. **Flash messages:** The flash components use daisyUI classes (`alert-info`, `alert-error`). They will render with daisyUI styling on top of the Precision Authority page. Flash component migration is a follow-up task.
4. **`<.input>` component:** The form input in the create modal uses daisyUI-styled `<.input>` with its own background, border, and radius. Inside the glassmorphic modal this will be visually jarring. Acceptable until the component is restyled globally, but may warrant a custom `class` override on the `<.input>` during implementation if it looks too broken.
5. **Theme toggle:** The theme toggle in the navbar remains active but daisyUI's dark theme is disabled. Clicking "dark" will set `data-theme="dark"` but daisyUI won't respond to it. The toggle will be removed when `layouts.ex` is migrated.
6. **Modal animation:** No entry/exit animation. The modal appears/disappears instantly. Animation will be added as a follow-up.

## Design System Rules (Reference)

These rules from DESIGN.md apply to all pages adopting the system:

1. **No-Line Rule:** No 1px borders for sectioning. Use background shifts only.
2. **Tonal Layering:** Level 0 (`ds-surface`) → Level 1 (`ds-surface-low`) → Level 2 (`ds-surface-card`).
3. **Ghost Border Fallback:** If a border is needed for accessibility, use `ds-outline-variant` at 20% opacity.
4. **Typography:** Manrope (`font-ds-heading`) for headings (bold, tight tracking). Inter (`font-ds-body`) for body/data.
5. **Hierarchy:** 3:1 contrast ratio between titles (`ds-on-surface`) and metadata (`ds-on-surface-variant`).
6. **Radius:** `ds-sharp` (2px) or `none` only. Never large radii.
7. **Shadows:** Only `shadow-ds-ambient` on floating elements. No drop shadows on cards.
8. **Signal colors:** `ds-secondary` (green) and `ds-tertiary` (orange) for success/warning only, never decorative.
9. **Spacing:** 4px grid alignment. Large gutters (5rem/6rem) between major sections.
10. **Empty states:** Use `ds-surface-dim` background.

## Scope Boundaries

**In scope:**
- `@theme` block in `app.css` with all `ds-` namespaced DESIGN.md tokens
- Self-hosted font files in `priv/static/fonts/`
- `@font-face` declarations in `app.css`
- Custom `shadow-ds-ambient` utility
- Disable daisyUI dark theme
- Org index page template rewrite (`organization_live/index.html.heex`)

**Out of scope:**
- Changes to `layouts.ex`
- Migration of other pages (family index, family show, gallery, etc.)
- Removing daisyUI
- Dark mode for design system
- `<.input>` component restyling
- Flash component restyling
