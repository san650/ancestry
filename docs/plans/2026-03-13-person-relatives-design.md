# Person Relatives — Design

## Overview

Add family relationships between persons. Only three relationship types are stored: parent, partner, and ex_partner. All other relationships (children, siblings, half-siblings) are inferred at query time from parent links.

## Stored Relationship Types

| Type | Semantics | Storage |
|------|-----------|---------|
| `parent` | A is parent of B | Directional: `person_a_id` = parent, `person_b_id` = child |
| `partner` | A and B are partners | Symmetric: `person_a_id < person_b_id` |
| `ex_partner` | A and B are ex-partners | Symmetric: `person_a_id < person_b_id` |

## Inferred Relationships (query-time, not stored)

- **Children** — inverse of parent: if A is parent of B, then B is a child of A
- **Siblings** — two people who share both parents
- **Half-siblings** — two people who share exactly one parent

## Data Model

### `relationships` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` (auto PK) | |
| `person_a_id` | `references :persons` | Parent (for parent type) or lower ID (for partner/ex_partner) |
| `person_b_id` | `references :persons` | Child (for parent type) or higher ID (for partner/ex_partner) |
| `type` | `text` | `"parent"`, `"partner"`, `"ex_partner"` |
| `metadata` | `map` (jsonb) | Polymorphic embed per type |
| `timestamps` | | |

**Indexes:**
- `unique_index([:person_a_id, :person_b_id, :type])` — no duplicate edges

**Constraints (changeset/context):**
- Max 2 parents per child (regardless of role)
- `person_a_id < person_b_id` enforced in changeset for partner/ex_partner types

### Polymorphic metadata (via `polymorphic_embed`)

- **`PartnerMetadata`** — `marriage_day`, `marriage_month`, `marriage_year` (integers, optional), `marriage_location` (string, optional)
- **`ExPartnerMetadata`** — all of PartnerMetadata + `divorce_day`, `divorce_month`, `divorce_year` (integers, optional)
- **`ParentMetadata`** — `role`: `"father"` | `"mother"`

## Module Structure

### Business logic

```
lib/ancestry/
  relationships.ex                          # Relationships context
  relationships/
    relationship.ex                         # Relationship schema
    metadata/
      partner_metadata.ex                   # marriage_day/month/year, marriage_location
      ex_partner_metadata.ex                # partner fields + divorce_day/month/year
      parent_metadata.ex                    # role (father/mother)
```

### Web layer

```
lib/web/
  live/
    person_live/
      show.ex                               # Extended: relationships section below person details
```

No new LiveView files — relationships are managed inline on the existing Person Show page.

## Context API (`Ancestry.Relationships`)

### Core CRUD

- `create_relationship(person_a, person_b, type, metadata_attrs)` — handles ID ordering for partner/ex_partner
- `update_relationship(relationship, attrs)` — update metadata
- `delete_relationship(relationship)` — remove a relationship
- `convert_to_ex_partner(relationship, divorce_attrs)` — carries marriage metadata over, adds divorce fields
- `change_relationship(relationship, attrs)` — changeset for forms

### Queries

- `list_relationships_for_person(person_id)` — all relationships (both directions)
- `get_parents(person_id)` — parents of a person
- `get_children(person_id)` — children of a person (inverse of parent)
- `get_partners(person_id)` — current partners
- `get_ex_partners(person_id)` — ex-partners
- `get_siblings(person_id)` — inferred from shared parents, returns:
  - `{person, parent_a_id, parent_b_id}` — full sibling (shares both parents)
  - `{person, parent_id}` — half-sibling (shares one parent)

## UI Design — Person Show Page

Two-column layout on desktop, stacked vertically on mobile (spouses first, then parents).

### Left column: "Spouses and Children"

- **Current person** highlighted at the top (photo, name, dates)
- **For each partner/ex_partner:**
  - Person card (photo thumbnail, name, birth_year–death_year)
  - Marriage info below (date, location) with edit pencil icon
  - If ex_partner: also shows divorce date, visually distinguished
  - Collapsible **"Children (N)"** section — children shared between current person and this partner
    - Each child: person card with photo, name, dates, edit pencil
    - "+ Add Child" button at the bottom
- **"+ Add Spouse"** button after all partner sections
- **"+ Add Child with Unknown Parent"** — for children with only one known parent

### Right column: "Parents and Siblings"

- **Father** — person card (if assigned), or empty state
- **Mother** — person card (if assigned), or empty state
- **Parents' marriage info** — if both parents exist and are partners, show their marriage metadata with edit pencil
- Collapsible **"Siblings (N)"** section — inferred from shared parents
  - Current person highlighted in the list
  - Each sibling: person card with photo, name, dates
  - Half-siblings labeled as such
- **"+ Add Parent"** button (hidden if 2 parents already assigned)

### Person cards

- Photo thumbnail (or gendered placeholder silhouette)
- Full name
- Birth year – death year (or just birth year if living)
- Gender-colored left border (blue for male, pink for female)
- Clicking the card navigates to that person's show page
- Edit pencil icon for editing the relationship metadata

### "Add" flows

All "add" buttons open a search dropdown to find an existing family member:
- Type-ahead search by name within the family
- Select a person, then fill relationship-specific metadata (role for parent, marriage fields for partner)

## Dependencies

- `polymorphic_embed ~> 5.0` — polymorphic embedded schemas for relationship metadata

## Design Decisions

- **Only 3 stored types** — parent, partner, ex_partner. Children, siblings, half-siblings are inferred from parent links. Simpler data model, no cascading logic needed.
- **Mixed storage semantics** — directional for parent (parent_id → child_id), symmetric for partner/ex_partner (lower_id, higher_id). Avoids redundant metadata.
- **Polymorphic embed** for metadata — type-safe per relationship, extensible without migrations.
- **Partial dates** for marriage/divorce — day/month/year as separate integers, consistent with existing birth/death date pattern on Person.
- **Convert partner to ex** — dedicated action carries marriage metadata over and prompts for divorce fields.
- **Search existing members** — "Add" flows search existing family members rather than creating new persons inline.
- **Max 2 parents** — role-agnostic cap of 2 parents per person, roles are father/mother.
- **Responsive layout** — two columns on desktop, stacked on mobile.
