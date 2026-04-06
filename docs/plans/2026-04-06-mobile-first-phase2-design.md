# Mobile-First Phase 2 — Design Spec

Continuation of the mobile-first refactor. Phase 1 converted Family Show, Gallery Show, Person Show, and Login. Phase 2 covers the remaining pages, introduces a unified navigation drawer, compact tree cards, and cross-cutting mobile fixes.

## 1. Unified Navigation Drawer

Remove the top header bar (logo, org name, logout) on mobile. Replace with a single ☰ hamburger on the left side of every page's toolbar. The hamburger opens a drawer sliding from the **left**.

### Drawer contents (top to bottom)

1. **App header** — logo + "Ancestry" branding + close (X) button
2. **Page actions** (context-dependent) — edit, delete, kinship, etc. Only the current page's actions appear. Pages with no actions omit this section entirely. Destructive actions (delete) visually separated with red text (`text-ds-error`).
3. **Page panel** (context-dependent) — on Family Show only: people search input + gallery list. Other pages: omitted.
4. **Divider**
5. **Organizations** — list of user's orgs, current one highlighted. Tap to switch org.
6. **Account** — Settings link, Log out link

### Drawer behavior

- Open/close via `JS.toggle_class()` — no server round-trip
- Slides from the left with backdrop overlay (`bg-black/60 backdrop-blur-sm`)
- Close via backdrop tap, X button, or Escape key
- Animation: 200ms ease-out slide
- Width: `w-[85vw] max-w-sm`

### Desktop (`lg:`)

- Header bar stays as-is (logo, org name, logout visible in the top bar)
- Hamburger icon hidden
- Page actions render directly in the toolbar as icon buttons
- Family Show side panel renders inline on the right

### Back navigation

- Back arrow removed from the mobile toolbar
- Floating action button (FAB) at the bottom-left of the viewport on mobile only
- Styling: `fixed bottom-4 left-4 z-30`, circular, `bg-ds-surface-card shadow-ds-ambient`, `min-w-[44px] min-h-[44px]`, back arrow icon
- Safe area: `pb-[env(safe-area-inset-bottom)]` offset
- Hidden on desktop (`lg:hidden`) — desktop keeps the back arrow in the toolbar

### Toolbar structure (mobile)

```
[☰]  Page Title
```

Single row. Hamburger on the left, page title next to it. No right-side icons on mobile (everything is in the drawer). Desktop toolbar remains unchanged.

## 2. Compact Person Card (TreeView)

### Mobile (default)

- Width: `w-[72px]`
- Square card with photo filling the area: `w-full h-[72px] object-cover`
- Name overlaid at bottom with gradient scrim: `bg-gradient-to-t from-black/60 to-transparent`
- Name text: `text-[9px] font-semibold text-white`, centered, max 2 lines
- Dates: hidden on mobile
- Gender border-top preserved: 2px pink (female), blue (male), gray (other)
- No-photo fallback: gender-colored icon centered on `bg-ds-surface-low`, name still overlaid at bottom
- Focused state: `ring-2 ring-ds-primary scale-105`

### Desktop (`lg:`)

- Current layout preserved: `w-28`, circular 56px photo, name below photo, dates below name

### Placeholder cards

- Scale down to match: `w-[72px] h-[72px]` on mobile
- Current size on desktop (`lg:w-28`)

### Couple card and subtree gaps

- Reduce gaps on mobile: `gap-4` (from `gap-8`) between couple cards and subtree children
- Desktop keeps `gap-8`

## 3. Organization Index

- Title: `text-lg font-bold` on mobile (from `text-2xl font-extrabold`)
- "New Organization" button: compact on mobile — smaller padding, smaller text
- Org cards: add a subtle icon (e.g., `hero-building-office-2`) and member/family count if available to give cards more visual weight
- Create modal: bottom-sheet on mobile (`flex items-end lg:items-center`, `w-full max-w-none lg:max-w-md`, `rounded-t-lg lg:rounded-ds-sharp`)

## 4. Family Index

- Title: `text-lg font-bold` on mobile
- Delete button on cards: currently `opacity-0 group-hover:opacity-100` — invisible on touch devices. Fix: always visible on mobile (`lg:opacity-0 lg:group-hover:opacity-100`), subtle styling so it doesn't dominate the card
- Delete modal: bottom-sheet on mobile (currently always `items-center`, change to `items-end lg:items-center`)

## 5. Gallery Index

Full daisyUI → design system conversion:

- `btn btn-primary` → `bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp ...`
- `btn btn-ghost` → `bg-ds-surface-high text-ds-on-surface rounded-ds-sharp ...`
- `card bg-base-100 shadow-sm border border-base-200` → `bg-ds-surface-card rounded-ds-sharp`
- `text-base-content` → `text-ds-on-surface`
- `text-base-content/40` → `text-ds-on-surface-variant`
- `hover:shadow-md` → `hover:bg-ds-surface-highest transition-colors`
- `text-error` → `text-ds-error`
- `rounded-lg` → `rounded-ds-sharp`
- `rounded-xl` → `rounded-ds-sharp`

Additional:
- Title: `text-lg font-bold` on mobile
- Delete button: same hover-only fix as Family Index
- Gallery card icon: use design system colors (`bg-ds-primary/10`, `text-ds-primary`)
- Modals (new gallery, delete confirmation): bottom-sheet on mobile

## 6. Person Index (Family Members)

Full daisyUI → design system conversion (same token mapping as Gallery Index):

- Title: `text-lg font-bold` on mobile
- Member cards: `bg-ds-surface-card rounded-ds-sharp`, photo circle `bg-ds-primary/10`, name `text-ds-on-surface`, birth year `text-ds-on-surface-variant`
- Search/link modal: bottom-sheet on mobile, design system tokens for inputs and buttons

## 7. Org People Index

- Table columns on mobile: hide Est. Age, Lifespan, Links, and Actions columns. Show only photo + name as a compact row. Use responsive utility classes (`hidden md:table-cell` or equivalent for the grid layout).
- Detail columns reappear on `md:` or `lg:`
- Action buttons (edit, delete): hidden on mobile, visible on desktop. On mobile, tapping the row navigates to the person detail page where actions are available.

## 8. Kinship

- Title: `text-lg font-bold` on mobile
- Person selector layout: stack selectors vertically on mobile (`flex-col sm:flex-row`) with swap button between them horizontally
- Two-branch tree on narrow screens: stack branches vertically instead of side-by-side. Left branch (Person A lineage) first, then right branch (Person B lineage). Common ancestor label connects them.
- Node cards: add `min-w-0` and truncation to prevent overflow

## 9. Cross-cutting fixes

### Toolbar titles

All pages with `text-2xl` toolbar titles: change to `text-lg font-ds-heading font-bold` on mobile. Affected pages:
- Organization Index
- Family Index
- Family New
- Person New
- Person Index (members)
- Gallery Index
- Kinship
- Org People Index

### Full-page form padding

Add `px-4` to content wrappers on mobile:
- Family New: `<div class="max-w-lg mx-auto mt-8">` → `<div class="max-w-lg mx-auto mt-8 px-4">`
- Person New: `<div class="max-w-2xl mx-auto mt-8">` → `<div class="max-w-2xl mx-auto mt-8 px-4">`

### Modal bottom-sheet pattern

All modals not yet using the mobile bottom-sheet pattern should be converted:
- Container: `flex items-end lg:items-center justify-center`
- Dialog: `w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp`
- Escape key handling preserved

Affected modals:
- Organization Index: create org modal
- Family Index: delete confirmation
- Gallery Index: new gallery modal, delete confirmation
- Person Index: link person modal

## Technical notes

- The unified navigation drawer is a new component in `lib/web/components/mobile.ex` or a new `lib/web/components/nav_drawer.ex`
- The drawer needs access to: current page's actions (passed as a slot), current org, list of user's orgs, and optionally page panel content (slot)
- The drawer is rendered in `layouts.ex` so it's available on every page
- Page-specific actions are passed from each LiveView via a slot or assign
- The FAB back button is also rendered in `layouts.ex`, with the back path passed as an assign or inferred from the current route
- The existing `bottom_sheet` component and its `sheet_action` sub-component are no longer needed on mobile (actions move to the drawer). They can be removed or kept for desktop-only use if desired.
- The existing right-side `drawer` component on Family Show is replaced by the page panel section inside the unified nav drawer
- Desktop layout is unchanged — header bar, toolbar actions, inline side panel all remain
