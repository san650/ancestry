# Kinship Naming, DNA Percentages & Tree Visualization

## Problem

The current kinship module uses repetitive "Great-Great-Great-Grandparent" naming instead of the standard genealogical convention "3rd Great Grandparent". It also lacks DNA shared percentages, an explanation of "X Times Removed", and shows kinship as a flat vertical path rather than a branching tree.

## Changes

### 1. Naming Convention Updates

Update `Ancestry.Kinship` classify/label functions.

**Ancestors (steps_a = 0):**

| Steps | New Name |
|-------|----------|
| 1 | Parent |
| 2 | Grandparent |
| 3 | Great Grandparent |
| 4 | Great Great Grandparent |
| 5+ | Nth Great Grandparent (e.g. "3rd Great Grandparent") |

**Descendants (steps_b = 0):** Mirror of ancestors — Great Grandchild, Great Great Grandchild, 3rd Great Grandchild, etc.

**Uncle/Aunt (steps_a = 1):**

| Steps B | New Name |
|---------|----------|
| 2 | Uncle & Aunt |
| 3 | Great Uncle & Aunt |
| 4 | Great Grand Uncle & Aunt |
| 5+ | Nth Great Grand Uncle & Aunt |

**Nephew/Niece (steps_b = 1):**

| Steps A | New Name |
|---------|----------|
| 2 | Nephew & Niece |
| 3 | Grand Nephew & Niece |
| 4 | Great Grand Nephew & Niece |
| 5+ | Nth Great Grand Nephew & Niece |

**Cousins:** No change — already correct.

### 2. DNA Percentage

Add `dna_percentage/3` to `Ancestry.Kinship`.

**Formula:**
- Direct line (one side is 0 steps): `100 / 2^steps`
- Siblings (both 1 step): 50%
- Collateral (both sides >= 1): `100 / 2^(steps_a + steps_b - 1)`
- Half-relationships: halve the result

**Display:** Show next to relationship label — e.g. "1st Cousin · ~12.5% shared DNA" — with a note that percentages are approximate.

### 3. Tree Visualization

Replace the current vertical linear path in `kinship_live.html.heex` with an inverted-V tree.

**Layout:**
- MRCA centered at top, spanning both columns
- Left column: Person A's lineage descending from MRCA
- Right column: Person B's lineage descending from MRCA
- Horizontal line under MRCA connecting both columns
- Vertical CSS lines connecting nodes in each column
- Highlighted endpoints (Person A and Person B) with `bg-primary/10 border-primary/30`
- Each node shows person name + relationship label (Parent, Grandparent, 1st Cousin, etc.)

**Implementation:** Pure HEEx + Tailwind CSS. No JS hooks, no SVG connectors. Split existing `kinship.path` into path_a (indices 0..steps_a) and path_b (steps_a..end). Two-column flex layout with CSS lines.

Lopsided paths (one column shorter) are fine — the shorter column simply ends earlier.

### 4. "X Times Removed" Footnote

Conditionally render below the tree when the relationship contains "Removed".

**Content:** "A 'removed' cousin is a relative from a different generation. The number of 'removes' indicates how many generations apart you are. For example, your parent's first cousin is your '1st Cousin, Once Removed' — one generation separates you from each other's generation."

**Styling:** Small muted text with info icon, 2-3 lines max.

## Approach

Modify existing `Ancestry.Kinship` module in-place. No new modules. Update the `kinship_live.html.heex` template for the tree layout and footnote.

## Files to Modify

- `lib/ancestry/kinship.ex` — naming helpers, add `dna_percentage/3`
- `lib/web/live/kinship_live.ex` — split path into path_a/path_b assigns, add `dna_percentage` assign
- `lib/web/live/kinship_live.html.heex` — tree layout, DNA display, footnote
