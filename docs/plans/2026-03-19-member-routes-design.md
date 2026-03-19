# Move Member Pages Outside Family Scope — Design

## Problem

Person/member pages are currently nested under `/families/:family_id/members/:id`. Since a person can belong to multiple families, their page should be a top-level route. The back button should return to the originating family and load that person in the TreeView.

## Solution

Move person show pages to `/people/:id` with an optional `?from_family=:family_id` query parameter that provides navigation context.

## Route Changes

```
# Remove:
live "/families/:family_id/members/:id", PersonLive.Show

# Add (top-level):
live "/people/:id", PersonLive.Show

# Keep as-is (family-scoped):
live "/families/:family_id/members/new", PersonLive.New
```

## PersonLive.Show Changes

- **Mount:** receives `%{"id" => id}` only (no `family_id`).
- **handle_params:** reads `from_family` from query params, loads the Family struct into `@from_family` (or `nil`).
- **Back button:** navigates to `/families/:family_id?person=:id` when `@from_family` is set. Hidden or navigates to `/` when `nil`.
- **Relationship links:** all point to `/people/:related_id?from_family=:family_id` (carrying context forward).
- **"Remove from family":** redirects to `/families/:family_id`.
- **"Delete person":** redirects to `/families/:family_id` if `from_family` set, otherwise `/`.

## Navigation Link Updates

All components that link to person show pages update from `/families/:family_id/members/:id` to `/people/:id?from_family=:family_id`:

- `PersonCardComponent` (tree card arrow icon)
- `PeopleListComponent` (sidebar details link)
- `PersonLive.Index` (member grid cards)
- `PersonLive.Show` (relationship links to related people)

## Back Button → TreeView Loading

When clicking back from `/people/:id?from_family=123`:
- Navigate to `/families/123?person=:id`
- `FamilyLive.Show.handle_params` reads `?person=` and sets the focus person + builds the tree
- The person is automatically loaded in the TreeView

## AddRelationshipComponent — Global Search

When adding relationships from PersonLive.Show (no family context), the component searches ALL people in the system, not just family members. Two separate function clauses handle the two modes (family-scoped vs global) — no nil-branching.

- `search_family_members/3` — used when `family` assign is a struct (from FamilyLive.Show tree)
- `search_all_people/2` — used when no family (from PersonLive.Show)
- Quick-create: `create_person/2` (with family) vs `create_person_without_family/1` (standalone)

## What Stays the Same

- `/families/:family_id/members/new` — creating a member is family-scoped
- `PersonLive.New` — unchanged
- Kinship routes — unchanged
- `FamilyLive.Show` — unchanged (already handles `?person=` param)
