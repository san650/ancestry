# Brutalist Design System — Design Spec

**Date:** 2026-04-25
**Branch:** `brutalist-design`
**Status:** Approved

## Overview

Complete visual overhaul of the Ancestry app from the current blue-tinted neutral palette (Manrope/Inter, daisyUI) to a brutalist design using a ColorHunt palette, new typography, custom components, and a unified CSS architecture. The goal is a consistent, bold, and readable interface across all pages.

## Color Palette

### Primary colors

From [ColorHunt palette](https://colorhunt.co/palette/1e104e452e5aff653fffc85c) plus black and white.

| CSS Variable | Hex | Name | Role |
|---|---|---|---|
| `--cm-indigo` | `#1E104E` | Deep Indigo | Header bg, heading color, card tag fills, nav active states |
| `--cm-plum` | `#452E5A` | Plum | Photo placeholders, avatar fallbacks, secondary dark surfaces |
| `--cm-coral` | `#FF653F` | Coral | Primary CTA, header accent stripe, stat accent borders, active nav |
| `--cm-golden` | `#FFC85C` | Golden | Highlight tags, badges, secondary CTA, nav active text |
| `--cm-black` | `#000000` | Black | Card borders, body text, heavy dividers |
| `--cm-white` | `#FFFFFF` | White | Page background, card backgrounds, text on dark |

### Derived tones

| CSS Variable | Hex | Role |
|---|---|---|
| `--cm-surface` | `#FAFAFA` | Toolbar bg, subtle recessed areas |
| `--cm-border` | `#E0E0E0` | Stat borders, subtle dividers |
| `--cm-text-muted` | `#999999` | Breadcrumbs, metadata, subtitles |
| `--cm-coral-hover` | `#E8552F` | Hover state for coral buttons |
| `--cm-indigo-hover` | `#150B3A` | Hover state for indigo/secondary buttons |

### Semantic colors

| CSS Variable | Hex | Role |
|---|---|---|
| `--cm-error` | `#BA1A1A` | Error states, destructive actions |
| `--cm-success` | `#006D35` | Success feedback |

### Semantic aliases

```css
--cm-color-primary: var(--cm-coral);
--cm-color-secondary: var(--cm-indigo);
--cm-color-accent: var(--cm-golden);
--cm-color-bg: var(--cm-white);
--cm-color-surface: var(--cm-surface);
--cm-color-text: var(--cm-black);
--cm-color-text-muted: var(--cm-text-muted);
```

## Typography

Three fonts, three roles. All free on Google Fonts, self-hosted as variable `.woff2` files.

| Font | Weights | CSS Variable | Role |
|---|---|---|---|
| **Bebas Neue** | 400 | `--cm-font-display` | Page titles, section headers, logo text, stat numbers. Always uppercase. |
| **Space Grotesk** | 400, 500, 700 | `--cm-font-body` | Body text, card names, form labels, nav text, subtitles. Mixed case. |
| **Space Mono** | 400, 700 | `--cm-font-mono` | Dates, metadata, tags, badges, buttons, breadcrumbs. Uppercase for labels. |

### Type scale (4px rhythm)

| Name | Size | Font | Usage |
|---|---|---|---|
| `display` | 28px / 24px mobile | Bebas Neue | Page titles |
| `heading` | 22px / 20px mobile | Bebas Neue | Section headings |
| `stat` | 26px / 22px mobile | Bebas Neue | Metric numbers |
| `body` | 14px | Space Grotesk | Default body text |
| `body-sm` | 13px | Space Grotesk | Card names, secondary body |
| `caption` | 12px | Space Grotesk | Subtitles |
| `mono` | 11px | Space Mono | Metadata, dates |
| `mono-sm` | 10px | Space Mono | Breadcrumbs, button text |
| `tag` | 8px | Space Mono | Tags, badges |
| `mono-xs` | 9px | Space Mono | Small labels |

### Heading behavior

- Bebas Neue headings use `letter-spacing: 1-2px`, always uppercase, always `--cm-indigo` color.
- Card names use Space Grotesk bold in black (mixed case).

## Logo & Favicon

**Logo mark:** Outlined white square (2.5px border) with Bebas Neue "A" in white. Displayed against the indigo header.

**Logo text:** "ANCESTRY" in Bebas Neue, `letter-spacing: 2px`, white.

**Favicon:** Same outlined square concept at 16px and 32px. Indigo background with white bordered "A" for visibility on browser tabs.

**Files to create:**
- `priv/static/images/logo.svg` — new SVG logo (replaces existing)
- `priv/static/favicon.ico` — new favicon

## Components

### Cards

- 2px solid black border, 2px border-radius
- Photo area: `--cm-plum` background, white initials as fallback
- **Desktop:** vertical layout — photo on top (120px height), body below, 2px black border separating photo from body
- **Mobile:** horizontal layout — 64px square photo on left, 2px black right-border separator, body on right
- Card body: Space Grotesk 700 for name, Space Mono 10px for metadata
- Tags: solid fill, 2px radius, Space Mono 8px uppercase
  - Role tags: `--cm-indigo` fill, white text
  - Highlight tags: `--cm-golden` fill, black text

### Stats / Metrics

- 1px `--cm-border` border, 2px `--cm-coral` top-accent, 2px radius
- Number: Bebas Neue 26px (22px mobile) in `--cm-coral`
- Label: Space Mono 8px uppercase in `--cm-text-muted`
- Desktop: row of 4. Mobile: row of 3 with abbreviated labels.

### Buttons

- **Primary:** `--cm-coral` background, white text, Space Mono 10px bold uppercase, 2px radius
- **Secondary:** `--cm-indigo` background, white text, same typography
- **Hover:** `--cm-coral-hover` (`#E8552F`) for primary, `--cm-indigo-hover` (`#150B3A`) for secondary
- No shadows, no gradients — flat brutalist

### Header

- `--cm-indigo` background, 3px `--cm-coral` bottom stripe
- Outlined white square logo (2.5px border) with Bebas Neue "A"
- "ANCESTRY" in Bebas Neue, `letter-spacing: 2px`
- Desktop: nav links in Space Mono 10px uppercase, `--cm-golden` for active
- Mobile: hamburger icon, nav links hidden

### Toolbar

- `--cm-surface` background, 1px `--cm-border` bottom border
- Breadcrumbs in Space Mono 10px (`mono-sm`) `--cm-text-muted`
- Primary action button on the right

### Mobile navigation

- Bottom nav bar with 4 items (Families, People, Gallery, More)
- Space Mono 8px uppercase labels
- Active item in `--cm-coral` with tinted icon background

### Form inputs

- 2px black border, 2px radius (matches card borders)
- Space Grotesk for input text, Space Mono for labels
- Focus state: 2px `--cm-coral` border

### Flash messages

- Positioned fixed top-right (replaces daisyUI toast)
- Left-border accent pattern:
  - Error: 3px `--cm-error` left border, light red-tinted background
  - Success: 3px `--cm-success` left border, light green-tinted background
  - Info: 3px `--cm-indigo` left border, light indigo-tinted background
- Space Grotesk body text, Space Mono for dismiss action

## CSS Architecture

### New file: `assets/css/palette.css`

Contains all `--cm-*` CSS custom properties and utility classes. Imported into `app.css` **before** the Tailwind import. The import order in `app.css` should be:

```css
@import "./palette.css";
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/web";
```

This ensures all `--cm-*` variables are available when Tailwind's `@theme` block references them.

### Tailwind `@theme` integration

Register `--cm-*` colors as Tailwind theme colors so templates can use `bg-cm-indigo`, `text-cm-coral`, `border-cm-golden`, etc. Replace all existing `ds-*` tokens.

Font variables registered so templates can use `font-cm-display`, `font-cm-body`, `font-cm-mono`.

### Utility classes in `palette.css`

- `.cm-tag` — base tag styling (font, size, padding, radius, uppercase)
- `.cm-tag-indigo`, `.cm-tag-golden` — fill variants
- `.cm-stat` — stat block with coral top-accent
- `.cm-card` — 2px black border, 2px radius

### Font files

Self-hosted in `priv/static/fonts/`:
- `bebas-neue.woff2` (replaces `manrope-variable.woff2`)
- `space-grotesk-variable.woff2` (replaces `inter-variable.woff2`)
- `space-mono-regular.woff2` (new)
- `space-mono-bold.woff2` (new)

### Removals

| Item | Location | Action |
|---|---|---|
| daisyUI plugin | `assets/vendor/daisyui.js` + import in `app.css` | Delete file, remove import |
| All `ds-*` CSS variables | `@theme` block in `app.css` | Replace with `cm-*` variables |
| All `ds-*` Tailwind classes | `.heex` templates, `.ex` component files | Replace with `cm-*` equivalents |
| daisyUI classes | `alert`, `btn`, `btn-primary`, `btn-soft`, `toast`, `base-*` | Replace with custom brutalist components |
| Manrope font | `priv/static/fonts/manrope-variable.woff2` | Delete |
| Inter font | `priv/static/fonts/inter-variable.woff2` | Delete |
| `shadow-ds-card`, `shadow-ds-ambient` | `app.css` custom classes | Delete (replaced by border-based design) |
| `--font-ds-heading`, `--font-ds-body` | `@theme` block | Replace with `--cm-font-*` |
| `--radius-ds-sharp` | `@theme` block | Replace with `--cm-radius: 2px` |

### What stays

- Tailwind v4 `@import "tailwindcss" source(none)` structure
- `@source` directives for CSS, JS, and `lib/web`
- Heroicons plugin
- PhoenixLiveView loading variant plugins (`phx-click-loading`, etc.)
- `animate.css` and `trix.css` imports
- Dark mode variant scaffolding (unused but harmless)

## daisyUI Replacement Map

| daisyUI component | Replacement |
|---|---|
| `alert`, `alert-info`, `alert-error` | Custom flash with 3px colored left-border accent |
| `btn`, `btn-primary`, `btn-soft` | Flat brutalist buttons — coral/indigo fill, Space Mono uppercase |
| `toast toast-top toast-end` | Custom positioned flash container (fixed top-right) |
| `base-100`, `base-200`, `base-300` | `cm-white`, `cm-surface`, `cm-border` |
| `themes: light` config | Removed entirely |
| Kinship calculator `base-*` colors | Mapped to `cm-*` palette |

## DESIGN.md Updates

Replace the current "Visual system" section with the following content:

### Visual system (replacement text)

- Use a bold, high-contrast brutalist palette:
  - Indigo: `#1E104E` — headers, headings, tag fills
  - Plum: `#452E5A` — photo placeholders, secondary dark surfaces
  - Coral: `#FF653F` — primary CTA, accent stripes, active indicators
  - Golden: `#FFC85C` — highlight tags, badges, secondary CTA
  - Black: `#000000` — card borders, body text
  - White: `#FFFFFF` — page backgrounds, card backgrounds
  - Surface: `#FAFAFA` — toolbar backgrounds, recessed areas
  - Border: `#E0E0E0` — stat borders, subtle dividers
  - Text muted: `#999999` — breadcrumbs, metadata
- Semantic colors for status only:
  - Error: `#BA1A1A`
  - Success: `#006D35`
- Use 2px solid black borders on cards and form inputs. No shadows.
- Use colored accent borders (coral top-accent on stats, colored left-accent on flash messages).
- Flat fills, no gradients. 2px border-radius throughout.

### Typography (replacement text)

- Use **Bebas Neue** for display headings and stat numbers. Always uppercase, always in indigo.
- Use **Space Grotesk** for body text, card names, form inputs, and subtitles.
- Use **Space Mono** for metadata, dates, tags, badges, buttons, and breadcrumbs.
- Keep hierarchy through font contrast: condensed display vs. wide body vs. monospace accents.

Also update the component guidance sections (buttons, cards, inputs) to reference the brutalist patterns: black borders, flat fills, no shadows, Space Mono uppercase for actions.

## Design Intensity

**Soft brutalist** — the design sits on the refined end of the brutalist spectrum:
- 2px borders (not 3-4px)
- 2px border-radius (not zero)
- Mixed-case card names (not ALL-CAPS everywhere, only headings)
- Clean toolbar with subtle borders (not heavy dividers)
- Colored accent borders on stats/flash (not heavy black borders everywhere)
- Flat fills, no shadows, no gradients

## Scope

This spec covers the visual system, color palette, typography, component patterns, CSS architecture, logo, and favicon.

**In scope:**
- All color, font, and component visual changes across all pages
- daisyUI removal and replacement with custom components
- New `palette.css` file and `@theme` registration
- Logo and favicon replacement
- Mobile bottom navigation bar (new UI component to replace the current mobile nav pattern)
- DESIGN.md rewrite

**Out of scope:**
- Data model or schema changes
- New features or functionality beyond the mobile bottom nav
- Route changes
- Backend logic
