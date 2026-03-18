# Tree View: Add Relationships In-Place

## Problem

Placeholder cards in the tree view ("Add Partner", "Add Child") navigate away to `PersonLive.Show`, breaking the user's flow. There is no "Add Parent" placeholder. Users should be able to add relationships directly from the tree view via an inline modal.

## Design

### Shared LiveComponent: `Web.Shared.AddRelationshipComponent`

A new LiveComponent at `lib/web/live/shared/add_relationship_component.ex` that encapsulates the full "add relationship" modal flow. Both `FamilyLive.Show` (tree view) and `PersonLive.Show` (detail page) use it.

**Required assigns from parent:**
- `person` -- the person we're adding a relationship for
- `family` -- the current family
- `relationship_type` -- `"partner"`, `"parent"`, or `"child"`
- `partner_id` -- (optional) co-parent ID when adding a child for a specific couple

**Internal state:**
- `step` -- `:search` | `:quick_create` | `:metadata`
- `search_query`, `search_results`, `selected_person`, `relationship_form`

**Flow:**
1. Search for existing family members
2. Select someone -> advance to metadata step, OR click "Create new" -> given name + surname form
3. After creating, auto-advance to metadata with new person selected
4. Save creates the relationship via `Ancestry.Relationships`, sends `{:relationship_saved, type, person}` to parent

**Absorbs `QuickCreateComponent`:** The quick-create form (given name + surname) is inlined into this component. `QuickCreateComponent` is deleted.

### Placeholder Cards

Rename `:spouse` to `:partner` throughout `PersonCardComponent`. Labels change from "Add Spouse" to "Add Partner".

Placeholders become buttons (not navigation links) that fire `phx-click="add_relationship"` events.

| Placeholder | Location | Condition |
|---|---|---|
| Add Partner | Next to focus person in couple card | Focus person has no current partner |
| Add Child | Below focus person | Root, no children |
| Add Parent | Above focus person in ancestor area | Fewer than 2 parents |

"Add Parent" is new -- renders above the center couple card when ancestors show fewer than 2 parents.

### FamilyLive.Show Changes

**New assign:** `@adding_relationship` -- `nil` or `%{type: string, person_id: integer}`

**New events:**
- `"add_relationship"` -- set from placeholder click
- `"cancel_add_relationship"` -- clear modal

**New callback:** `{:relationship_saved, type, person}` -- rebuild tree, refresh people list, keep focus person, clear modal.

### PersonLive.Show Refactor

Remove inline modal template and relationship-adding event handlers (`add_relationship`, `search_members`, `select_person`, `save_relationship`, `start_quick_create`, `cancel_quick_create`). Replace with the shared `AddRelationshipComponent`. Keep `{:relationship_saved, ...}` callback to reload relationships.
