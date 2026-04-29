# Toolbar & Menu Reorganization — Design Spec

**Date:** 2026-04-26

## Goal

Standardize toolbar actions, kebab menus, and mobile hamburger menus across all pages. Establish consistent patterns for action placement, button styling, and menu structure.

## Cleanup (done)

Removed leftover unused LiveView modules (no route in router):

- `lib/web/live/person_live/index.ex` + `index.html.heex` — deleted
- `lib/web/live/gallery_live/index.ex` + `index.html.heex` — deleted

## Global Patterns

### Desktop Toolbar

- **All text buttons, no icons.** Every toolbar action is a text button with a background so it does not melt into the toolbar.
- **Primary actions:** coral background, white text (e.g. "New Organization", "Upload", "Add Memory").
- **Secondary actions:** 2px solid black border, surface background (e.g. "Select", "Edit", "Kinship").
- **"Select"** is always named "Select" and always uses the secondary button style.
- **View toggles** (Graph/Tree) use a segmented text pill — active state gets indigo background, inactive gets surface background.

### Kebab Menu

- Triggered by a `⋮` button (2px solid black border, surface background) at the right end of the toolbar.
- **All text options, no icons.**
- **Top portion** (above separator): regular actions.
- **Separator** (horizontal line): only present when there are regular actions above AND edit/delete container actions below. If the kebab only contains delete (no regular actions, no edit), omit the separator.
- **Edit container** (e.g. "Edit Family"): below separator.
- **Delete container** (e.g. "Delete Family"): last item, red text (`#BA1A1A`).

### Selection Mode

Unified pattern across all pages that support multi-select (Organization Index, Family Index, Gallery Show, People List Family, People List Org, Vault Show):

1. Toolbar shows "Select" text button.
2. Clicking "Select" enters selection mode — checkboxes appear on items.
3. **Desktop:** A sticky secondary toolbar appears with black background, white text counter ("3 SELECTED"), and context-specific action buttons (e.g. "Delete" with error-red background).
4. **Mobile:** Same selection flow but actions appear in a bottom drawer (slide-up sheet overlay anchored to the bottom of the viewport) instead of a sticky toolbar. This is distinct from the removed bottom mobile toolbar — the bottom drawer only appears during active selection and dismisses when selection mode exits.

### Mobile Hamburger Menu

- **All text options, no icons.**
- **No "Organizations" navigation link** — the website/logo icon in the header navigates to root (`/org`).
- **No bottom mobile toolbar** — removed globally from all pages.
- **Structure:**
  1. Page-specific actions (if any)
  2. Separator
  3. Settings
  4. Accounts (admin only)
  5. Log Out
- Destructive actions (delete) are red text and placed last in the page-specific section.

### Filter Chips

On pages with search/filter bars (People List Family, People List Org, Birthday Index):

- **Text-only chips, no icons.**
- Gold highlight (`#FFC85C`) background when active.
- Located in a filter bar below the toolbar (People lists) or in the toolbar itself (Birthdays).

### Table Row Actions

- **Keep as icon buttons** per row (pencil for edit, trash for delete, link-slash for remove).
- These are the only place icons are used for actions.

---

## Per-Page Specification

### 1. Organization Index (`/org`)

**Desktop toolbar:**
- "Select" (secondary button)
- "New Organization" (primary/coral button)

**Kebab menu:** None.

**Mobile hamburger:**
- Select
- New Organization
- —
- Settings
- Accounts (admin)
- Log Out

---

### 2. Family Index (`/org/:org_id`)

**Desktop toolbar:**
- "Select" (secondary button)
- "New Family" (primary/coral button)
- Kebab `⋮`

**Kebab menu:**
- People

**Mobile hamburger:**
- Select
- People
- New Family
- —
- Settings
- Accounts (admin)
- Log Out

---

### 3. Family Show (`/org/:org_id/families/:family_id`)

**Desktop toolbar:**
- Breadcrumb
- Graph/Tree segmented toggle (text)
- "Kinship" (secondary button)
- "Birthdays" (secondary button)
- Kebab `⋮`

**Kebab menu:**
- Print Tree
- Manage People
- Import from CSV
- Create Subfamily
- —
- Edit Family
- Delete Family (red)

**Mobile hamburger:**
- Graph View / Tree View (single item, text shows the alternate view to switch to, e.g. "Tree View" when currently in graph mode)
- Tree Settings (mobile-only — on desktop these controls are in the collapsible bottom drawer panel)
- Kinship Calculator
- Birthdays
- Manage People
- Import from CSV
- Create Subfamily
- Edit Family
- Print Tree
- Delete Family (red)
- —
- Settings
- Accounts (admin)
- Log Out

---

### 4. Gallery Show (`/org/:org_id/families/:family_id/galleries/:id`)

**Desktop toolbar:**
- Breadcrumb
- "Select" (secondary button)
- "Masonry" / "Uniform" toggle (secondary button, text changes)
- "Upload" (primary/coral button)

**Kebab menu:** None.

**Selection mode:** Matches Organization Index pattern — sticky secondary toolbar with counter + "Delete".

**Mobile hamburger:**
- Select
- Upload Photos
- Masonry / Uniform
- —
- Settings
- Accounts (admin)
- Log Out

---

### 5. Person Show (`/org/:org_id/people/:id`)

**Desktop toolbar:**
- Breadcrumb (context-aware)
- "Edit" (secondary button)
- Kebab `⋮`

**Kebab menu:**
- Remove from Family (conditional — only when `from_family` query param is present)
- Convert to Non-family (conditional — only for family members)
- —
- Delete Person (red)

**Mobile hamburger:**
- Edit
- Remove from Family (conditional)
- Convert to Non-family (conditional)
- Delete Person (red)
- —
- Settings
- Accounts (admin)
- Log Out

---

### 6. People List — Family (`/org/:org_id/families/:family_id/people`)

**Desktop toolbar:**
- Breadcrumb
- "Select" (secondary button)

**Filter bar (below toolbar):**
- Search input
- "Unlinked" chip (text-only, gold toggle)
- "Non-family" chip (text-only, gold toggle)

**Kebab menu:** None.

**Selection mode:** Sticky secondary toolbar with counter + "Remove from Family".

**Table row actions:** Icon buttons (pencil for edit, link-slash for remove).

**Mobile hamburger:**
- Select
- —
- Settings
- Accounts (admin)
- Log Out

Selection actions appear in bottom drawer on mobile.

---

### 7. People List — Org (`/org/:org_id/people`)

**Desktop toolbar:**
- Breadcrumb
- "Select" (secondary button)

**Filter bar (below toolbar):**
- Search input
- "No family" chip (text-only, gold toggle)
- "Non-family" chip (text-only, gold toggle)

**Kebab menu:** None.

**Selection mode:** Sticky secondary toolbar with counter + "Delete".

**Table row actions:** Icon buttons (pencil for edit, trash for delete).

**Mobile hamburger:**
- Select
- —
- Settings
- Accounts (admin)
- Log Out

Selection actions appear in bottom drawer on mobile.

---

### 8. Vault Show (`/org/:org_id/families/:family_id/vaults/:vault_id`)

**Desktop toolbar:**
- Breadcrumb
- "Select" (secondary button)
- "Add Memory" (primary/coral button)
- Kebab `⋮`

**Kebab menu:**
- Delete Vault (red)

**Selection mode:** Sticky secondary toolbar with counter + "Delete".

**Mobile hamburger:**
- Select
- Add Memory
- Delete Vault (red)
- —
- Settings
- Accounts (admin)
- Log Out

---

### 9. Memory Show (`/org/.../memories/:memory_id`)

**Desktop toolbar:**
- Breadcrumb
- "Edit" (secondary button)
- Kebab `⋮`

**Kebab menu:**
- Delete Memory (red)

**Mobile hamburger:**
- Edit
- Delete Memory (red)
- —
- Settings
- Accounts (admin)
- Log Out

---

### 10. Birthday Index (`/org/:org_id/families/:family_id/birthdays`)

**Desktop toolbar:**
- Breadcrumb
- "Show all" filter chip (text-only, gold toggle)

**Kebab menu:** None.

**Mobile hamburger:**
- —
- Settings
- Accounts (admin)
- Log Out

Note: "Show all" filter is in the toolbar, not the hamburger menu. Remove back arrow.

---

### 11. Kinship Calculator (`/org/:org_id/families/:family_id/kinship`)

**Desktop toolbar:** Breadcrumb only. No actions.

**Kebab menu:** None.

**Mobile hamburger:**
- —
- Settings
- Accounts (admin)
- Log Out

---

### 12. Person New (`/org/:org_id/families/:family_id/members/new`)

**Desktop toolbar:** Breadcrumb only. Form actions in body.

**Kebab menu:** None.

**Mobile hamburger:**
- —
- Settings
- Accounts (admin)
- Log Out

---

### 13. Memory Form (new + edit)

**Desktop toolbar:** Breadcrumb only. Form actions in body.

**Kebab menu:** None.

**Mobile hamburger:**
- —
- Settings
- Accounts (admin)
- Log Out

---

### 14. Family New (`/org/:org_id/families/new`)

**Desktop toolbar:** Breadcrumb only. Form actions in body.

**Kebab menu:** None.

**Mobile hamburger:**
- —
- Settings
- Accounts (admin)
- Log Out

---

## Pages excluded from this spec

- **Admin pages** (Account Management): skipped.
- **Family Print** (`/print`): print-only page, no interactive toolbar.
- **Account Login/Settings/Confirmation**: auth pages, separate concern.
