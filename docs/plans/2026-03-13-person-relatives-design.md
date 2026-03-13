# Person Relatives — Design

## Overview

Add family tree relationships between persons. Relationships are stored as directed edges in a graph, with polymorphic metadata per relationship type using `polymorphic_embed`. Includes cascading logic (adding a parent auto-creates sibling links) and a family-scoped tree visualization using d3 + dagre.

## Relationship Types

| Type | Cardinality | Direction (A → B) |
|------|-------------|-------------------|
| `partner` | Max 1 per person | A is partner of B |
| `ex_partner` | 0+ | A is ex-partner of B |
| `sibling` | 0+ | A is sibling of B |
| `half_sibling` | 0+ | A is half-sibling of B |
| `child` | 0+ | A is child of B |
| `parent` | Max 1 mother, max 1 father | A is parent of B |
| `second_parent` | 0+ | A is second parent of B |

## Data Model

### `relationships` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` (auto PK) | |
| `person_a_id` | `references :persons` | Source person |
| `person_b_id` | `references :persons` | Target person |
| `type` | `text` | Relationship type |
| `metadata` | `map` (jsonb) | Polymorphic embed |
| `timestamps` | | |

**Indexes:**
- `unique_index([:person_a_id, :person_b_id, :type])` — no duplicate edges

**Cardinality constraints (changeset + context layer):**
- Max 1 current partner per person
- Max 1 mother (parent with role=mother) per person
- Max 1 father (parent with role=father) per person

### Polymorphic metadata structs (via `polymorphic_embed`)

- **`PartnerMetadata`** — `marriage_day`, `marriage_month`, `marriage_year`, `marriage_location` (all optional, partial-date pattern)
- **`ExPartnerMetadata`** — same as Partner + `divorce_day`, `divorce_month`, `divorce_year`
- **`ParentMetadata`** — `role`: `"father"` or `"mother"`
- **`SecondParentMetadata`** — `role`: `"father"` or `"mother"`
- **`SiblingMetadata`** — empty struct (placeholder)
- **`HalfSiblingMetadata`** — empty struct (placeholder)
- **`ChildMetadata`** — empty struct (placeholder)

## Module Structure

### Business logic

```
lib/ancestry/
  relationships.ex                          # Relationships context
  relationships/
    relationship.ex                         # Relationship schema (directed edge)
    metadata/
      partner_metadata.ex                   # Polymorphic embed for partner
      ex_partner_metadata.ex                # Polymorphic embed for ex-partner
      parent_metadata.ex                    # Polymorphic embed for parent
      second_parent_metadata.ex             # Polymorphic embed for second parent
      sibling_metadata.ex                   # Embedded schema (empty)
      half_sibling_metadata.ex              # Embedded schema (empty)
      child_metadata.ex                     # Embedded schema (empty)
```

### Web layer

```
lib/web/
  live/
    person_live/
      show.ex                               # Extended: relationships section + add relationship inline form
    family_live/
      tree.ex                               # Family tree visualization page
```

### Assets

```
assets/js/
  family_tree_hook.js                       # JS hook for d3/dagre tree rendering
```

## Context API (`Ancestry.Relationships`)

### Core CRUD

- `create_relationship(person_a, person_b, type, metadata_attrs)` — create a single directed edge
- `delete_relationship(relationship)` — remove a relationship
- `update_relationship(relationship, attrs)` — update metadata

### Queries

- `list_relationships_for_person(person_id)` — all relationships (both directions)
- `get_parents(person_id)` — parents of a person
- `get_children(person_id)` — children of a person
- `get_partner(person_id)` — current partner
- `get_siblings(person_id)` — siblings + half-siblings
- `get_family_graph(family_id)` — all persons in family + all relationships between them (for tree view)

### Cascading logic (`create_relationship_with_cascades`)

- `create_relationship_with_cascades(person_a, person_b, type, metadata_attrs)` — creates the relationship and triggers cascading updates

**When adding a parent to person B:**
1. Find all other children of that parent
2. For each other child, check if they share both parents with B → create `sibling` edge
3. If they share only one parent → create `half_sibling` edge

**When adding a sibling:**
1. Copy parent links — the new sibling gets the same parents as the existing person

**When converting partner to ex_partner:**
1. Remove the `partner` edges
2. Create `ex_partner` edges with existing marriage metadata + new divorce fields

### Changeset helper

- `change_relationship(relationship, attrs)` — return changeset for forms

## Routes

```
/families/:family_id/tree                   # FamilyLive.Tree — family tree visualization
```

Relationship management happens on `PersonLive.Show` (already routed at `/families/:family_id/members/:id`).

## UI/UX

### Person Show page — Relationships section

Below existing person details, grouped by type:

- **Parents** — listed with role (Father/Mother), photo thumbnail, name. "Add Parent" button.
- **Partner** — current partner with marriage info. "Add Partner" button (hidden if one exists).
- **Ex Partners** — list with marriage/divorce dates. "Add Ex Partner" button.
- **Siblings** — list with sibling/half-sibling label. "Add Sibling" button.
- **Children** — list of children. "Add Child" button.
- **Second Parents** — list with role. "Add Second Parent" button.

Each "Add" button expands an **inline form** with two modes:
1. **Search existing** — search family members by name, click to select, then fill relationship metadata
2. **Create new** — inline person creation form (name, dates, gender, photo) + relationship metadata

### Family Tree page (`/families/:family_id/tree`)

- Accessible from "Family Tree" link on `FamilyLive.Show`
- Uses d3 + dagre for layout, rendered via `phx-hook` with `phx-update="ignore"`
- Server pushes graph data (nodes + edges) via `push_event`
- Layout rules:
  - Parents appear above their children
  - Partners appear side-by-side, connected with a horizontal line
  - Children of the same parents are grouped horizontally below
  - Siblings connected via shared parent lines
  - Detached persons (no relationships) appear in a separate area
- Clicking a node navigates to that person's show page
- Each node shows: photo thumbnail, display name, birth year

## Dependencies

- `polymorphic_embed ~> 5.0` — polymorphic embedded schemas for relationship metadata
- `d3` (npm) — SVG rendering for tree visualization
- `dagre` (npm) — directed graph layout algorithm

## Design Decisions

- **Directed edges** — one row per relationship, type encodes direction (A is X to B)
- **Polymorphic embed** for metadata — type-safe per relationship, extensible without migrations
- **Partial dates** for marriage/divorce — consistent with existing birth/death date pattern
- **Cascading sibling creation** — adding a parent auto-links siblings based on shared parents
- **Family-scoped tree** — tree rendered per family, not per person
- **d3 + dagre** — proven library combination for hierarchical graph layout
- **Inline add-relationship form** — stays in context on Person Show page
