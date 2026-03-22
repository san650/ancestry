# Design System Specification: The Precision Authority

## 1. Overview & Creative North Star
**Creative North Star: "The Architectural Ledger"**

This design system is engineered for high-stakes decision-making. It rejects the cluttered "widget-based" aesthetic of traditional dashboards in favor of an editorial, high-contrast layout that mirrors a Swiss-designed financial broadsheet.

By utilizing **Organic Brutalism**, we move beyond the generic "SaaS look." We achieve authority through intentional asymmetry—placing heavy data visualizations against expansive white space. We break the "template" feel by using dramatic shifts in typographic scale and deep charcoal accents to anchor the eye, ensuring that in a sea of data, the most critical "signal" is never lost in the "noise."

---

## 2. Colors: High-Contrast Functionalism
The palette is rooted in a stark, monochromatic base, allowing signal colors to function as true alerts rather than decorative elements.

### The Palette
* **Primary & Neutrals:** We use `#000000` (Primary) and `#0b1c30` (On-Surface) to create a "Deep Charcoal" foundation. The background (`#f8f9ff`) provides a cool, clinical crispness.
* **The Signal Layer:** `Secondary` (`#006d35`) and `Tertiary` (`#ffb77d`) are reserved strictly for "Success" and "Warning" states. They must never be used for decorative branding.

### Implementation Rules
* **The "No-Line" Rule:** Prohibit 1px solid borders for sectioning. Structural boundaries must be defined solely through background shifts. Use `surface-container-low` (`#eff4ff`) for sidebars and `surface-container-highest` (`#d3e4fe`) for inactive utility panels.
* **Surface Hierarchy & Nesting:** Treat the UI as stacked sheets of vellum. A `surface-container-lowest` (`#ffffff`) card should sit atop a `surface-container-low` (`#eff4ff`) background to create a "lift" through color value rather than structural lines.
* **The "Glass & Gradient" Rule:** For floating modals or "quick-view" overlays, use Glassmorphism. Apply `surface-container-lowest` at 80% opacity with a `20px` backdrop-blur.
* **Signature Textures:** For primary CTAs, apply a subtle linear gradient from `primary` (`#000000`) to `primary_container` (`#1c1b1b`). This adds a "machined metal" depth that feels premium and intentional.

---

---

## 3. Typography: The Scanning Engine
We pair the architectural stability of **Manrope** for headers with the high-legibility "workhorse" characteristics of **Inter** for data.

* **Display & Headlines (Manrope):** Use `display-lg` (3.5rem) sparingly for high-level metric summaries. The geometry of Manrope communicates modern authority.
* **Data & Body (Inter):** All tabular data must use `body-md` (0.875rem) or `label-md` (0.75rem). Inter’s tall x-height ensures that complex strings of alphanumeric data remain legible at small scales.
* **Hierarchy Strategy:** Create a 3:1 contrast ratio between titles and metadata. Use `on_surface_variant` (`#444748`) for secondary labels to recede into the background, allowing the primary data points in `on_surface` (`#0b1c30`) to pop.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "soft" for this system’s brutalist edge. We define depth through light and tone.

* **The Layering Principle:**
1. **Level 0 (Base):** `surface` (`#f8f9ff`)
2. **Level 1 (Sub-section):** `surface-container-low` (`#eff4ff`)
3. **Level 2 (Interactive Card):** `surface-container-lowest` (`#ffffff`)
* **Ambient Shadows:** If a floating element (like a dropdown) requires a shadow, use a "Tinted Ambient" approach. Use the `on-surface` color at 6% opacity with a `32px` blur and an `8px` vertical offset. This mimics natural light passing through a glass pane.
* **The "Ghost Border" Fallback:** If a border is required for accessibility, use `outline-variant` (`#c4c7c7`) at **20% opacity**. Never use 100% opaque borders; they disrupt the "Architectural Ledger" flow.

---

## 5. Components: Precision Primitives

### Input Fields & Controls
* **Input Fields:** Use `surface-container-lowest` with a `none` border and a bottom-only stroke of `outline-variant`. On focus, transition the bottom stroke to `primary` (`#000000`) with a 2px weight.
* **Buttons:**
* *Primary:* Solid `#000000` with `#ffffff` text. Corner radius: `sm` (0.125rem) for a sharp, technical look.
* *Secondary:* `surface-container-high` (`#dce9ff`) background with `on_surface` text.
* **Cards & Lists:** **Strictly forbid divider lines.** Use `1.5` (0.375rem) or `2` (0.5rem) spacing increments to separate rows. Use a hover state of `surface-container-highest` to highlight a row’s active area.
* **Data Chips:** Use `secondary_container` (`#8df9a8`) for positive trends. Text should be `on_secondary_container` (`#007439`) for maximum contrast and WCAG compliance.

### Dashboard-Specific Components
* **The "Metric Block":** A large `headline-lg` value sitting atop a `label-sm` title. No containers; the value is anchored by its own typographic weight.
* **The "Trend Sparkline":** Monochromatic (Primary) by default, only turning `secondary` (Green) or `error` (Red) if the delta exceeds a 10% threshold.

---

## 6. Do's and Don'ts

### Do
* **Do** use `20` (5rem) and `24` (6rem) spacing for major section gutters to allow the data to breathe.
* **Do** use `surface-dim` (`#cbdbf5`) for empty states to create a "hollowed-out" visual cue.
* **Do** align all data to a strict 4px grid. Precision is the aesthetic.

### Don't
* **Don't** use "Information Blue." If something is informative but not a success/error, use the `Primary` charcoal.
* **Don't** use large corner radii. Stick to `sm` (0.125rem) or `none`. The system should feel "cut," not "molded."
* **Don't** use centered text for data tables. Always left-align strings and right-align numerical values for rapid scanning.
