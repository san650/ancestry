# Design System Specification: The Precision Authority

## UI/UX rules

Apply these rules to all interface work. Build mobile first, then enhance for desktop. Keep one interaction model across breakpoints.

### Core principles

- Prioritize clarity, hierarchy, and fast scanning over decoration.
- Start with the smallest useful layout and progressively enhance.
- Use whitespace and tonal separation before adding borders or shadows.
- Do not rely on hover for any essential information or action.
- On desktop, use extra space to improve scanning and efficiency, not to redesign flows.
- Keep layouts bounded on large screens.
- Follow a strict 4px spacing rhythm.

### Visual system

- Use a restrained neutral palette:
  - Primary: `#000000`
  - On-surface: `#0b1c30`
  - Background: `#f8f9ff`
  - Surface low: `#eff4ff`
  - Surface high: `#dce9ff`
  - Surface highest: `#d3e4fe`
- Reserve accent colors for semantics only:
  - Success: `#006d35`
  - Warning: `#ffb77d`
- Do not add decorative “information blue” accents.
- Prefer tonal layers over heavy dividers.
- Borders are a fallback. If required, keep them subtle and low contrast.
- Prefer tonal depth over strong shadows. Use soft shadows only for floating layers.
- Use sharp or lightly rounded corners. Avoid large radii.

### Typography

- Use **Manrope** for headings and **Inter** for body text, labels, and tables.
- Keep hierarchy obvious but avoid oversized mobile headings.
- Use tighter line height for headings and more relaxed line height for body text.
- Body text must be readable on small screens without zoom.
- Metadata and helper text may be smaller, but must remain legible.
- In tables, left-align text and right-align numbers.

### Layout and responsiveness

- Mobile is the default layout.
- Prefer vertical flow on mobile.
- Default to one column on mobile unless two columns remain clearly readable.
- Increase columns progressively on larger screens for comparison and scanning.
- Prevent unintended horizontal overflow.
- Keep readable max-width constraints on desktop.
- Collapse sidebars into drawers or top-level navigation on smaller screens.
- Expose persistent navigation, filters, or supporting panels on desktop only when they improve efficiency.

### Interaction

- Design for touch first, pointer second.
- Make tap targets comfortable on mobile.
- Keep primary actions obvious and easy to reach.
- Avoid destructive actions that are too easy to trigger on small screens.
- Ensure keyboard and screen reader accessibility.
- Hover may enhance the UI, but must never be required.

### Components

#### Inputs and controls
- Prefer clean surfaces and obvious focus states.
- Avoid heavy outlined fields unless stronger separation is necessary.
- Subtle borders or bottom strokes are acceptable for controls.

#### Buttons
- Primary buttons: dark background, light text.
- Secondary buttons: lighter tonal surface, dark text.
- Keep primary actions visible without hover.

#### Cards and lists
- Use spacing and background tone instead of divider lines wherever possible.
- Surface the primary action directly.
- Do not hide essential actions or information behind hover.

#### Data chips and dashboard elements
- Use semantic colors only for true status or trend meaning.
- Emphasize important metrics with typography and spacing, not heavy containers.
- Keep charts neutral by default; switch to semantic colors only when the data meaning justifies it.

#### Photo galleries
- Mobile: one clear focal image, stacked or horizontally browsable layouts, minimal thumbnails.
- Desktop: multi-column browsing for faster scanning.
- Preserve image aspect ratios and avoid cramped small-screen grids.

#### Card galleries
- Mobile: single-column by default; use two columns only if still clearly readable.
- Desktop: add columns to improve comparison and discovery.
- Show extra metadata on desktop only when it would clutter mobile cards.

#### Modals
- Mobile: prefer full-screen modals or bottom sheets.
- Desktop: use centered dialogs or side panels with constrained widths.
- Do not force long mobile workflows into cramped dialogs.

#### Menus
- Mobile: prefer sheets, drawers, accordions, or full-screen selectors.
- Desktop: dropdowns, popovers, toolbars, and side navigation are acceptable.
- Keep labels visible; use icon-only actions sparingly.

#### Menus with many options
- Do not compress long option sets into small mobile dropdowns.
- Mobile: use grouped lists, segmented controls, accordions, or full-screen selectors.
- Prioritize common actions and move secondary ones behind a clear “more” pattern.
- Add grouping and search when option lists are long.

### Tailwind guidance

- Treat mobile styles as the default.
- Use responsive utilities only to enhance larger breakpoints.
- Keep responsive behavior explicit, predictable, and consistent.
- Favor reusable utility patterns over one-off styling.

### Component decisions

Page-specific layout and interaction decisions are stored in `COMPONENTS.jsonl`. Each line is a JSON object with `component` and `description` fields. Grep for a component name (e.g. `family-show-mobile`, `shared-drawer`, `gallery-show-lightbox-mobile`) to find the relevant decision. When adding new components or making new design decisions, append a new JSON line to `COMPONENTS.jsonl`.

### Final checks

Before shipping, verify:

- Mobile is the simplest clear usable version.
- Desktop improves efficiency without changing the core interaction model.
- Content is readable on small screens.
- Actions are obvious without hover.
- Tap targets are comfortable.
- Layouts do not overflow horizontally.
- Hierarchy comes from typography, spacing, and tonal separation first.
- Semantic colors are used only for semantic meaning.
