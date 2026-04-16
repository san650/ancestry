# Photo Lightbox Side Panel — Tonal Redesign

## Summary

The lightbox side panel (People + Comments) currently relies on thin border lines (`border-white/10`) to separate every section. The project's `DESIGN.md` is explicit: "use whitespace and tonal separation before adding borders or shadows." This plan removes those borders and re-expresses the panel using a 4-step tonal scale on the dark backdrop, applied to both the desktop side panel and the mobile full-screen overlay.

Scope is tightly limited to the side panel surfaces. Out of scope: the lightbox top bar, the desktop thumbnail strip, the people-tagging dropdown.

## Visual System

A dark-mode reading of the existing design system: tonal layers replace borders.

| Layer | Token | Used for |
|-------|-------|----------|
| L0 | `bg-black` | Lightbox photo backdrop (unchanged) |
| L1 | `bg-white/[0.03]` | Side panel base — slightly lifted from the photo backdrop |
| L2 | `bg-white/[0.06]` | Section "cards" (People, Comments) — the new dividers |
| L3 | `bg-white/[0.10]` | Comment composer surface, ambient hover state on rows |
| L4 | `bg-white/[0.16]` | Selected/active comment, action chips |

Section radii: `rounded-ds-sharp` for the tonal cards (matches `rounded-lg` ≈ 8–10px elsewhere in the project). No outlines, no border lines, no shadows on the cards themselves.

Text contrast ramp (no change to the palette tokens, only opacities):

- Section labels: `text-white/90`, font `Manrope` bold, 12px, uppercase, `tracking-wide`
- Body text in comments: `text-white/85`
- Author name: `text-white/95` (slightly stronger than body to anchor the row)
- Timestamps and meta: `text-white/40`
- **Empty state text: `text-white/50`** (up from current `text-white/30` — the headline readability bug)
- Disabled / placeholder: `text-white/40`

## Layout

### Desktop side panel (`lg:` breakpoint and up)

```
fixed-width 320px column, lives inside the existing flex row in the lightbox
─────────────────────────────────────────
│ panel base = L1, flex-col, p-2, gap-2
│
│  ┌─ panel header row (flex justify-between, p-2) ─┐
│  │  h3 "Photo info"               [×] close       │
│  └────────────────────────────────────────────────┘
│
│  ┌─ People card (L2, rounded, p-2.5) ─────────────┐
│  │  card-title row: "PEOPLE"  [count chip]        │
│  │  ── content (list or empty state) ──            │
│  │  optional max-h-48 overflow-y-auto              │
│  └────────────────────────────────────────────────┘
│
│  ┌─ Comments card (L2, rounded, p-2.5, flex-1) ──┐
│  │  card-title row: "COMMENTS"  [count chip]     │
│  │  ── scrollable comment list (flex-1) ──        │
│  │  ── composer (L3 tonal block, no border) ──    │
│  └────────────────────────────────────────────────┘
│
─────────────────────────────────────────
```

### Mobile full-screen panel (default; replaces side panel below `lg:`)

Same primitives; differences:

- Larger tap targets (`min-h-[44px]` on rows and buttons)
- Person rows expose an explicit `×` remove icon (no hover state on touch)
- Selected comment expands inline with `Edit` / `Delete` tonal chips below the text — replaces today's absolute-positioned floating chip on desktop
- Add a **Download** tonal block at the very bottom of the panel (today's lightbox top-bar download icon is hidden on mobile because the panel covers it)
- People card capped at `max-h-[30vh]` to avoid eating the screen when many people are tagged

**Mobile header layout after removing the bottom border:** the panel header row remains a single flex row at the top of the panel (`flex justify-between items-center px-2 py-2`) — h3 title left-aligned, close `×` button right-aligned with `min-w-[44px] min-h-[44px]`. The L1 panel base provides the visual containment; nothing replaces the border.

### Header label

Unify to **"Photo info"** in both modes. The current "Photo Info" / "People" split (mobile vs desktop) doesn't match either screen — both contain People + Comments.

## Component Inventory

### Section card primitive

A small markup pattern, not a Phoenix function component (it's used twice in the same template; abstracting would over-engineer).

```heex
<div class="bg-white/[0.06] rounded-ds-sharp p-2.5 flex flex-col gap-2">
  <div class="flex items-center gap-2 px-1 pb-1">
    <h4 class="text-xs font-ds-heading font-bold text-white/90 tracking-wide uppercase">
      {section_label}
    </h4>
    <span :if={count > 0} class="text-[11px] text-white/50 bg-white/[0.08] px-1.5 py-0.5 rounded-full">
      {count}
    </span>
  </div>
  {inner_content}
</div>
```

### Empty state primitive

Inline within each section. Same shape both sections so the panel has a consistent "nothing here yet" rhythm.

```heex
<div class="text-center py-5 text-white/50">
  <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-white/[0.04] mb-2">
    <.icon name={icon} class="w-4 h-4 text-white/40" />
  </div>
  <p class="text-[12.5px] leading-snug">{message}</p>
</div>
```

Section-specific copy:

| Section | Icon | Message |
|---------|------|---------|
| People (mobile) | `hero-user` | "No people tagged yet." |
| People (desktop) | `hero-user` | "Click on the photo to tag people." |
| Comments | `hero-chat-bubble-left-right` | "No comments yet. Be the first to add one." |

### Composer (new comment input)

```heex
<div class="bg-white/[0.10] rounded-ds-sharp px-3 py-1.5 flex items-end gap-2">
  <textarea ... class="flex-1 bg-transparent border-0 text-sm text-white placeholder-white/40 resize-none focus:outline-none focus:ring-0 ..." />
  <button type="submit" class="h-8 w-8 rounded-md bg-primary hover:bg-primary/80 ...">
    <.icon name="hero-paper-airplane" class="w-4 h-4" />
  </button>
</div>
```

The textarea loses its individual `bg-white/10 border border-white/15 rounded-lg` shell. The composer-as-a-whole is now the L3 tonal block; the textarea is transparent inside it. The send button keeps its existing `bg-primary hover:bg-primary/80` styling — the gradient in the mockups was illustrative, not prescriptive.

### Selected comment

- Mobile (existing inline-compact format): the row gains `bg-white/[0.16]` instead of today's `bg-white/10`. Action chips appear inline below the text.
- Desktop (existing bubble format): the selected-row pattern is **mobile-only** in this pass. The desktop branch has no `phx-click="select_comment"` wiring today and adding it is out of scope. Keep the existing hover-revealed floating action chip on desktop. (Future work: unify selection model across breakpoints — tracked in `COMPONENTS.jsonl` under a follow-up component note.)

### Person row

```heex
<div class="flex items-center gap-3 px-1.5 py-2 rounded-ds-sharp hover:bg-white/[0.06] min-h-[44px] lg:min-h-0">
  <.user_avatar account={person} size={:sm} />
  <span class="flex-1 text-sm text-white/85 truncate">{display_name(person)}</span>
  <button class="p-1 text-white/40 hover:text-white/80 lg:opacity-0 lg:group-hover:opacity-100">
    <.icon name="hero-x-mark" class="w-4 h-4" />
  </button>
</div>
```

Mobile: remove button always visible. Desktop: hover-revealed (existing pattern).

## Files Changed

| File | Change |
|------|--------|
| `lib/web/components/photo_gallery.ex` | Rewrite the panel branch inside `lightbox/1` (lines ~204–315): replace border-divided sections with two L2 tonal cards inside an L1 panel base. Update header label to "Photo info". Add download tonal block on mobile. |
| `lib/web/live/comments/photo_comments_component.ex` | Replace section header + border treatment with the section-card primitive. Drop `border-white/10` dividers around list and input. Promote empty state to L2-card-internal pattern with bumped opacity. Update composer to L3-tonal-block (textarea inside, no individual border/bg). Update selected comment to use L4 (`bg-white/[0.16]`) instead of L2 (`bg-white/10`). |
| Test files | E2E test in `test/user_flows/` covering: open lightbox → toggle panel → empty state visible → add a comment → select it → edit / delete. (See "Testing" section.) |

## Behavior Preserved

This is a visual refactor. All existing behavior is preserved:

- Open / close panel via the info-circle button in the lightbox top bar
- Add / edit / delete / select comments
- Tag / untag people (untag still desktop-only via the existing PhotoTagger flow)
- Stream-based real-time updates (PubSub `comment_created` / `comment_updated` / `comment_deleted`)
- Permissions enforced through `Ancestry.Permissions` (`can_edit?` / `can_delete?`)
- Auto-grow textarea via `TextareaAutogrow` hook
- Mobile tap-to-select pattern via `phx-click="select_comment"`
- Person highlight on hover via `PersonHighlight` hook

No changes to: contexts (`Ancestry.Comments`), schemas (`PhotoComment`), migrations, routes, LiveView event handlers, PubSub topics, Oban workers.

## Testing

A new E2E test in `test/user_flows/lightbox_panel_test.exs` covering the side-panel surfaces. Conventions follow `test/user_flows/CLAUDE.md`.

**Given** an authenticated account with at least one processed photo and the lightbox open
**When** the user toggles the info panel
**Then**
- Both `data-section="people"` and `data-section="comments"` cards are visible
- Empty states render their respective copy at readable contrast (assert presence of the text, not opacity — opacity is visual)

**When** the user types a comment and submits
**Then**
- The new comment appears in the stream
- The composer textarea clears
- The empty-state copy disappears

**When** the user taps a comment they own (mobile-style flow)
**Then**
- Edit and Delete buttons appear inline
- Tapping Delete with confirmation removes the comment from the list

Use the project's `test_id/1` helper from `Web.Helpers.TestHelpers` on the new tonal cards: `{test_id("lightbox-people-card")}` and `{test_id("lightbox-comments-card")}`. This emits `data-testid` attributes that are stripped in production builds (per `test/CLAUDE.md`). E2E tests target them via `Web.E2ECase.test_id/1`.

## Risks and Trade-offs

**Risk: tonal contrast on low-quality displays.** The L1 → L2 step is `0.03 → 0.06` opacity-on-black, which is subtle. On a glossy, color-managed laptop screen this reads beautifully; on a cheap external monitor in bright sun it might look like one flat panel. Mitigation: the primary signal is the rounded card edge + internal padding, not the tonal step. Even if the bg disappears, the layout still parses.

**Risk: the section-card pattern recurs once.** It's used twice (People + Comments) in one template. Abstracting it into a `section_card/1` function component is tempting but adds indirection for two callers. Keep it inline. If a third caller appears later, extract.

**Risk: removing the panel header bottom border changes weight.** Today the close X sits below a border; visually it's a chrome bar. After: the close X floats in negative space above the first card. This is intentional — the cards do the dividing — but is the kind of change that *feels* wrong before you live with it. If it doesn't land, fall back: keep the panel header but apply `bg-white/[0.04]` instead of a border. Decide after seeing it in the running app.

**Out of scope (deferred):** The people-tagging dropdown (visible in the screenshot) has the same border-heavy problem and is a natural follow-up. Documented in `COMPONENTS.jsonl` as a known issue for a future pass.

## Component Decision Log

After implementation, append to `COMPONENTS.jsonl`:

```json
{"component": "gallery-show-lightbox-panel", "description": "Dark-mode tonal panel with 4-step scale (L1 0.03, L2 0.06, L3 0.10, L4 0.16 on white). People + Comments rendered as L2 cards on L1 base. No border dividers — section separation via card edges and whitespace. Empty states at text-white/50. Composer is an L3 tonal block with a borderless textarea inside. Selected comment uses L4 instead of an outline."}
```

Update existing entry `gallery-show-lightbox-desktop` to reference this panel pattern.

## Implementation Notes

- Class strings should use the project's `ds-` design tokens where they exist (e.g. `rounded-ds-sharp`, `font-ds-heading`, `font-ds-body`). Use raw `bg-white/[0.06]` etc. for tonal-on-dark since the existing `bg-ds-surface-*` tokens are light-palette only.
- Do **not** introduce new design tokens for these dark tonal layers in this pass — the existing palette is light-mode and adding "dark surface" tokens is a separate, larger decision. Inline opacity values are fine for one self-contained component; promote later if the pattern recurs across surfaces.
- Keep the `phx-no-format` annotations on `whitespace-pre-line` text spans (per `docs/learnings.jsonl`).
- The `<.user_avatar>` component is already imported in `Web` and handles the photo-vs-initials fallback. Use as-is.
