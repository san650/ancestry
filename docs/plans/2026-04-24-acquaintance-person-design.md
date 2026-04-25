# Acquaintance Person (Non-Family Member)

**Date:** 2026-04-24
**Status:** Design

## Problem

The app currently treats all persons as family members who participate in the relationship graph and tree view. Users need to tag people in photos and mention people in vault memories who are not part of the family tree — friends, neighbors, colleagues, etc. These people should exist in the system with minimal details but should not clutter the tree view or relationship graph.

## Solution

Add a `kind` enum field to the `Person` schema with values `"family_member"` (default) and `"acquaintance"`. The `kind` field controls which UI features a person participates in, without changing how they relate to families, photos, or memories.

## Data Model

### Migration

- Add column `kind` (`:string`, default: `"family_member"`, null: false) to `persons` table
- Backfill: all existing persons get `"family_member"`

### Person Schema

- Add `:kind` to `@cast_fields` in `Person.changeset/2`
- Add `field :kind, :string, default: "family_member"`
- Validate inclusion in `["family_member", "acquaintance"]` in changeset
- Add helper: `def acquaintance?(%__MODULE__{kind: "acquaintance"}), do: true`

### Invariants (enforced at context level)

- Acquaintance persons **do** have `FamilyMember` records (they belong to families)
- Acquaintance persons can belong to multiple families
- Acquaintance persons must have **zero** `Relationship` records
- Block relationship creation in `Relationships.create_relationship/4` if either person is an acquaintance — return `{:error, :acquaintance_cannot_have_relationships}`
- Prevent acquaintances from being set as the family's default person (`People.set_default_member/2`)

## Behavior by Kind

| Feature | `family_member` | `acquaintance` |
|---|---|---|
| Belongs to families | Yes | Yes |
| Has relationships (parent, partner, etc.) | Yes | No |
| Appears in tree view | Yes | No |
| Appears in relationship creation dropdowns | Yes | No |
| Appears in kinship calculator selectors | Yes | No |
| Appears in photo tagging dropdowns | Yes | Yes |
| Appears in memory mention dropdowns | Yes | Yes |
| Appears in people lists (family & org) | Yes | Yes (with "Non-family" badge) |
| Shows relationships section on person show | Yes | No |
| Appears in birthday calendar | Yes | Yes |
| Can be set as family default person | Yes | No |

## UI Changes

### Person Creation

- **PersonFormComponent:** Add a checkbox at the bottom: "This person is not a family member (acquaintance)". Unchecked by default. Sets `kind: "acquaintance"` when checked.
- **Photo tagging inline create:** Same checkbox when creating a new person during photo tagging.
- **Memory mention inline create:** Same checkbox if creating a person from vault/memory UI.
- **Quick-create in AddRelationshipComponent:** No checkbox — that flow creates relationships, so the person is always `kind: "family_member"`.
- **CSV import:** Imported persons default to `kind: "family_member"`. No `kind` column in CSV. This is correct since CSV imports create relationships.

### People Lists (Family & Org)

- **"Non-family" badge:** Acquaintance persons display a subtle pill/tag badge next to their name.
- **"Non-family only" filter:** New filter toggle that shows only `kind: "acquaintance"` persons.
- **"Unlinked only" filter** (family list) / **"No family only" filter** (org list): Scoped to `kind: "family_member"` persons only. Acquaintances are expected to have no relationships, so including them would be noise.
- **Search:** Applies to all persons regardless of kind.

### Person Show Page

**For acquaintance persons:**
- Show header, name, basic info, dates, photo, family memberships — same as family members.
- **Hide** the relationships section entirely.
- **Hide** the "Add relationship" action.
- Show photos section (same as family members).
- Show a prominent **"Convert to family member"** banner/button (since acquaintances have no relationships section, there's space). Updates `kind` to `"family_member"` — person already belongs to families, just a confirmation click.

**For family member persons:**
- Everything stays the same as today.
- **"More actions" dropdown:** Add "Convert to non-family" option.
  - **Blocked** if the person has any relationships — show a warning: "Remove all relationships before converting."
  - If no relationships: updates `kind` to `"acquaintance"` with a confirmation dialog.

### Tree View

- Exclude `kind: "acquaintance"` persons at the query level.
- `People.list_people_for_family/1` stays unfiltered (returns all kinds) — it's used by people lists which need both.
- Add a new function `People.list_family_members_for_family/1` that filters to `kind: "family_member"` — used by `FamilyGraph`, `PersonTree`, and `KinshipLive`.

### Relationship & Kinship Dropdowns

- `People.search_family_members/3` and `People.search_all_people/3`: Filter to `kind: "family_member"` only.
- Kinship calculator person selectors: Only show `kind: "family_member"` persons.

### Photo Tagging & Memory Mentions

- No filtering — both family members and acquaintances appear in these dropdowns.

## Conversion Flows

### Acquaintance → Family Member

- **Where:** Person show page, prominent "Convert to family member" button/banner.
- **Action:** Updates `kind` from `"acquaintance"` to `"family_member"`.
- **Prerequisites:** None — person already belongs to families.
- **Confirmation:** Simple confirmation click, no modal.

### Family Member → Acquaintance

- **Where:** Person show page, "More actions" dropdown → "Convert to non-family".
- **Action:** Updates `kind` from `"family_member"` to `"acquaintance"`. If the person is the default member of any family, clear that flag.
- **Prerequisites:** Person must have zero relationships. If relationships exist, show warning: "Remove all relationships before converting."
- **Confirmation:** Confirmation dialog explaining the change.

## i18n

All new user-facing strings require `gettext` calls and Spanish translations in `priv/gettext/es-UY/LC_MESSAGES/default.po`. Key strings:
- Checkbox label, "Non-family" badge, "Non-family only" filter label
- "Convert to family member" / "Convert to non-family" actions
- Warning: "Remove all relationships before converting"
