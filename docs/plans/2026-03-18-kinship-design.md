# Kinship Feature Design

## Summary

Build a tool to select two people from a family and determine their relationship (kinship). Shows the relationship label (e.g. "First Cousins") and a vertical path visualization from Person A through the Most Recent Common Ancestor (MRCA) down to Person B.

## Data Model & Algorithm

No new database tables. The feature is read-only, traversing existing `relationships` rows.

**New module: `Ancestry.Kinship`** — pure business logic.

**Algorithm: Bidirectional BFS**

1. Build ancestor maps for both Person A and Person B: `%{person_id => {generation_depth, parent_path}}`
2. Expand one generation at a time, alternating between A and B
3. When ancestor sets intersect, that person is the MRCA
4. Use generation counts (`steps_a` from A to MRCA, `steps_b` from MRCA to B) to classify the relationship
5. Reconstruct path: walk from A up to MRCA, then down to B

**Relationship classification:**

- `steps_a == 0` or `steps_b == 0`: direct ancestor/descendant (parent, grandparent, etc.)
- `steps_a == steps_b == 1`: siblings
- `steps_a == 1` or `steps_b == 1`: aunt/uncle or niece/nephew
- `min(steps_a, steps_b) - 1`: cousin degree (1st, 2nd, 3rd...)
- `abs(steps_a - steps_b)`: times removed
- Half-relationships: detected by checking if MRCA is a single person vs a couple

**Max traversal depth:** 10 generations (configurable) to prevent runaway queries.

**Traverses all relationships globally**, not restricted to family members only.

## Route & LiveView

**Route:** `/families/:family_id/kinship` -> `Web.KinshipLive`

**Query params:** `?person_a=123&person_b=456` (both optional, for pre-population)

**LiveView assigns:**

- `@family` — current family
- `@people` — all people in the family (for selectors)
- `@person_a` / `@person_b` — selected people (or nil)
- `@result` — kinship calculation result (or nil)

**Events:**

- `select_person_a` / `select_person_b` — pick a person
- `clear_person_a` / `clear_person_b` — reset a selection
- `swap` — swap Person A and Person B

**Behavior:**

- When both people are selected, automatically compute and display the result (no "Calculate" button)
- If a person is deselected, clear the result
- The "Kinship" button on the family show page navigates to `/families/:family_id/kinship`, appending `?person_a=:id` if a focus person exists
- Same person cannot be selected for both — disabled in the opposite selector

## UI Layout & Visualization

**Page structure:**

- Back arrow linking to the family show page
- Title: "Kinship"
- Two person selector cards side by side with a swap button between them
- Below: the result area

**Person selectors:** Searchable dropdowns listing family members. Each shows the person's photo, name, and a clear button.

**Result area (when both selected):**

- Relationship label prominently displayed (e.g. "First Cousins")
- Directional label (e.g. "Person B is Person A's first cousin")
- Path visualization (always vertical, top-to-bottom):
  - Person A at the top
  - Cards connected by vertical lines going up to MRCA, then down to Person B
  - Each node shows the person name (or couple names) and relationship label relative to Person A (e.g. "Parents", "Grandparents", "Uncle", "Cousin")

**No result:** "No common ancestor found" message.

## Testing

**Unit tests (`test/ancestry/kinship_test.exs`):**

- Direct relationships: parent/child, grandparent/grandchild, great-grandparent
- Siblings (full and half)
- Aunt/uncle, niece/nephew
- First cousins, second cousins
- Cousins once removed, twice removed
- No relationship found (unrelated people)
- Same person selected (edge case)
- Half-relationships (single shared ancestor vs couple)

**E2E test (`test/user_flows/calculating_kinship_test.exs`):**

- Given a family with known relationships
- Navigate to the kinship page
- Select two people and verify the relationship label and path are displayed
- Swap people and verify the labels update correctly
- Clear a selection and verify the result disappears
- Select unrelated people and verify "No common ancestor found"

## Kinship Rules Reference

### Core Principles

- **MRCA:** Nearest shared ancestor (person or couple)
- **Generation levels:** Siblings share generation. First cousin = child of parent's sibling.
- **Removed:** Different generation count between the two people relative to the MRCA.

### Relationship Terms

- Siblings: share parents
- Aunt/Uncle: sibling of parent
- Niece/Nephew: child of sibling
- First Cousin: share grandparents
- Second Cousin: share great-grandparents
- Third Cousin: share great-great-grandparents
- Grandaunt/Granduncle: sibling of grandparent

### Removed Calculation

1. Find cousin degree: `min(steps_a, steps_b) - 1`
2. Find removed count: `abs(steps_a - steps_b)`

### Half Relationships

Share only one ancestor instead of a pair (e.g. half-siblings share one parent, half-cousins are children of half-siblings).
