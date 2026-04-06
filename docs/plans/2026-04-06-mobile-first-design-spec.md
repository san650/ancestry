# Mobile-First Design Refactor

Refactor priority pages to be mobile-first, adhering to DESIGN.md rules. Component-by-component approach — build shared patterns on the first page, reuse on subsequent pages.

## Priority pages

1. Family Show (tree view)
2. Gallery Show (photo grid + lightbox)
3. Person Show (profile + relationships)
4. Login

## Approach

Component-by-component refactor. Each page is restructured mobile-first with `sm:`/`md:`/`lg:` enhancements. Shared primitives (drawer, bottom sheet menu, full-screen overlay, mobile toolbar) are built as encountered and reused across pages. Desktop layouts are restructured so the mobile view falls out naturally from the same component tree.

## Shared components

### Drawer

Slide-in panel from the right for mobile. Hidden on `lg:` where content renders inline. Single component instance — on mobile, the panel gets `translate-x-full` by default and slides in via CSS transform (`translate-x-0`) when open. On desktop, transform is removed and it renders inline.

- Open/close state managed client-side via `JS.toggle_class()` — no server round-trip for instant feel
- Backdrop overlay (`bg-black/60 backdrop-blur-sm`), close via backdrop tap, X button, or Escape
- Animation: 200ms ease-out slide
- Content slot for arbitrary content

### Bottom sheet menu (overflow actions)

Replaces the overflow/more button actions on mobile. Triggered by an ellipsis icon button (`hero-ellipsis-vertical`). On mobile, opens as a bottom sheet sliding up from the bottom of the screen — per DESIGN.md "prefer sheets, drawers" for mobile menus. On desktop, those actions render directly in the toolbar instead (bottom sheet not used).

- Open/close via `JS.toggle()` — no server round-trip
- Backdrop overlay, close via backdrop tap or Escape
- Action items are full-width rows with icon + label, minimum 48px height for touch targets
- Animation: 200ms ease-out slide up

### Mobile toolbar

Sticky top bar with back navigation, page title, and action buttons. Minimum 44px tap targets. Desktop enhances with more visible actions and wider spacing.

### Full-screen overlay

Extends existing modal pattern. Uses `min-h-[100svh] w-full` as base with `h-dvh` as progressive enhancement for modern browsers. Used for lightbox, photo comments, upload modal, and login on mobile. Animation: 200ms ease-out fade-in or slide-up.

- Focus trapping for accessibility
- `aria-modal="true"` and appropriate `role` attributes

## Page designs

### Family Show

**Mobile (default):**
- Toolbar: back arrow + family name + drawer toggle + bottom sheet menu (edit, delete)
- "Create subfamily" and "manage people" are removed from mobile — users manage people via the people search in the drawer
- Tree canvas: full-width, natural scroll in both directions (`overflow-auto`). Scrollbars hidden via `scrollbar-width: none` / `::-webkit-scrollbar { display: none }` for a clean canvas feel. Touch drag to pan works natively
- Person interaction: first tap focuses/selects the person (centers, highlights with a visible ring or scale effect). Second tap on the already-focused person navigates to their profile. Tapping empty canvas or a different person changes focus. No long-press needed — tap and drag are clearly distinguishable by the browser's native scroll detection
- Keyboard/screen reader: person cards have `role="button"`, `aria-label` with person name, and `tabindex="0"`. Enter key focuses, Enter on focused navigates. Focus ring visible via standard `:focus-visible` styling
- Drawer (two sections):
  - People search: text input at top, type-to-suggest with debounce. No pre-populated list. Results show name + small photo. Tapping a result focuses that person in the tree (scrolls to them, highlights). Empty state: helper text "Type to search people"
  - Gallery list: vertical list of gallery cards (name + photo count). Tap navigates to the gallery show page

**Desktop (`lg:`):**
- Side panel inline on the right (`lg:grid-cols-[1fr_18rem]`), same content as drawer
- Toolbar actions expanded — edit, delete, kinship visible directly
- Drawer toggle hidden
- Click-to-select on person cards (existing behavior preserved)

### Gallery Show

**Mobile (default):**
- Toolbar: back arrow + gallery name + select button (primary, always visible) + bottom sheet menu (upload, layout toggle masonry/uniform)
- Photo grid: 2-column masonry (`columns-2`), `sm:columns-3` on larger phones. Generous gap (`gap-2`). Aspect ratios preserved via `break-inside-avoid`
- Selection mode: tap select button to enter mode. Tap photos to toggle selection. Bottom action bar appears fixed at bottom with `pb-[env(safe-area-inset-bottom)]` for notch safety. Shows count + actions (delete, move). Z-index above content, below overlays
- Upload: accessed from bottom sheet menu. Opens as full-screen overlay with file list + progress indicators. User can close while uploads continue in background. Drag-and-drop disabled on mobile
- Photo tagging: disabled on mobile. Available only on desktop where click-to-tag doesn't conflict with navigation

**Lightbox (mobile):**
- Full-screen dark background
- Swipe left/right to navigate (JS touch gesture hook with ~50px distance threshold and velocity detection)
- Top bar: close (X) button + info/comments button
- Position indicator: "3 of 47" text centered in top bar between close and info buttons
- No thumbnail strip
- Info/comments button opens full-screen overlay with people tags + comments. Overlay must be closed before navigating to next photo (swipe disabled while overlay is open)
- Download available in the info overlay
- Single-photo galleries: swipe disabled, no position indicator shown
- At first/last photo: swipe shows a subtle bounce/resistance effect, does not wrap around

**Desktop (`lg:`):**
- All toolbar actions visible directly (select, upload, layout toggle)
- Photo grid: `md:columns-4 lg:columns-5`
- Lightbox: side panel for people/comments, thumbnail strip at bottom, arrow key navigation, photo tagging enabled
- Drag-and-drop overlay preserved

### Person Show

**Mobile (default):**
- Hero photo header: full-width image, `max-h-64 w-full object-cover`. Name overlaid at bottom of the photo with gradient scrim (`bg-gradient-to-t from-black/50 to-transparent`), white text (`text-white font-ds-heading text-xl font-bold`), padded from bottom (`p-4`)
- No photo fallback (hero only): person's initials (first letters of given + surname) centered on `bg-ds-surface-low`, same `max-h-64` height. Small person cards in relationship lists use a generic placeholder icon instead of initials
- Toolbar: back arrow + bottom sheet menu (edit, remove from family, delete). Delete is visually separated (red text) in the bottom sheet to avoid accidental activation
- Content order:
  1. Hero photo with name overlay
  2. Key facts: compact vertical list — birth date/location, death date/location (if applicable), gender, families (tappable chips that navigate to the family show page), alternate names (small badges)
  3. Relationships: vertical stack of cards. Each group (spouses & children, parents & siblings) as a card with `bg-ds-surface-card` on `bg-ds-surface-low`. Person entries show small photo (or placeholder icon) + name, tappable to navigate to their person show page. "Add relationship" button at bottom of section
  4. Tagged photos: photos where this person is tagged via the photo tagger. 2-column grid (`sm:grid-cols-3`), tap opens the gallery lightbox at that photo's position in its gallery

**Desktop (`lg:`):**
- Photo: constrained card on the left (`w-64 h-64 object-cover rounded-ds-sharp`), name as heading + key facts as list beside it — horizontal layout (`lg:flex lg:gap-8`)
- Name is no longer overlaid on desktop; it sits beside the photo
- Relationships: two-column grid (`lg:grid-cols-2`) — spouses/children left, parents/siblings right
- Tagged photos: `md:grid-cols-4 lg:grid-cols-5`
- Toolbar actions visible directly (edit, remove, delete)

### Login

**Mobile (default):**
- Full-height viewport form, vertically centered
- Logo (Ancestry logo) centered at top with generous spacing (`pt-16 pb-8`)
- Large email + password inputs, comfortable tap targets. Full-width
- Full-width primary submit button (gradient primary style)
- "Forgot password?" link below submit button
- Note: registration route is currently disabled in the router

**Desktop (`lg:`):**
- Same form, `max-w-sm` centered vertically and horizontally on the page
- `bg-ds-surface` background
- No decorative side panels

## Technical notes

- All decisions are also stored in `COMPONENTS.jsonl` for grep-based lookup. New decisions during implementation should be appended there
- Existing design tokens (colors, fonts, surface hierarchy) are reused — no new CSS variables needed
- JS hooks needed: swipe gesture detection for lightbox navigation
- Tree interaction uses standard `phx-click` — no custom JS hooks needed (tap-to-focus, tap-focused-to-navigate)
- Drawer open/close and bottom sheet use `Phoenix.LiveView.JS` commands for client-side state — no server round-trips
- Tailwind mobile-first: base classes are mobile, `sm:`/`md:`/`lg:` for progressive enhancement
- Modals on mobile become full-screen overlays; on desktop they stay as centered dialogs
- Edit forms (family edit, relationship edit, person form) render inside full-screen overlays on mobile. Date picker grids reflow to stack vertically on mobile. Person picker uses the same type-to-suggest pattern as the drawer people search
- Scrollbar hiding on tree canvas: CSS `scrollbar-width: none` + `::-webkit-scrollbar { display: none }` while preserving scroll functionality
