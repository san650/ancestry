---
date: 2026-03-21
topic: organization-tenant
---

# Organization as Base Tenant

## What We're Building

Add an Organization entity as the top-level tenant for the entire application. All existing models (families, people, galleries, photos, relationships, comments) become scoped to an organization. The landing page lists organizations, and all routes move under `/org/:org_id/`.

## Why This Approach

The app currently has Family as the implicit top-level entity. Adding Organization above it enables multi-tenant isolation — people, families, and all related data in one organization are invisible to another.

## Key Decisions

- **org_id placement**: Add `organization_id` to `families` and `persons` tables only. Galleries, photos, comments, and relationships inherit org scope through their parent entities (Family or Person). Avoids redundant columns.

- **Person belongs to one org**: A person has a direct `organization_id` foreign key (not many-to-many). If the same real person needs to exist in two orgs, they're two separate records. Simplest isolation model.

- **Organization schema**: Minimal — `name` (string, required), `has_many :families`, `has_many :people`. No slug, logo, or description for now.

- **Route structure**:
  ```
  /                                              → OrganizationLive.Index
  /org/:org_id                                   → FamilyLive.Index
  /org/:org_id/families/new                      → FamilyLive.New
  /org/:org_id/families/:family_id               → FamilyLive.Show
  /org/:org_id/families/:family_id/galleries/:id → GalleryLive.Show
  /org/:org_id/families/:family_id/members/new   → PersonLive.New
  /org/:org_id/families/:family_id/kinship       → KinshipLive
  /org/:org_id/families/:family_id/people        → PeopleLive.Index
  /org/:org_id/people/:id                        → PersonLive.Show
  ```

- **Seed data**: Wrap existing Thompson family data in a default "Default Organization".

- **Data isolation**: All context functions that list/search entities will be scoped by `organization_id`. Cross-org queries are prevented at the context layer.

## Scope of Changes

1. **New schema**: `Ancestry.Organizations.Organization`
2. **New context**: `Ancestry.Organizations`
3. **New LiveView**: `OrganizationLive.Index` (landing page)
4. **Migration**: Create `organizations` table, add `organization_id` FK to `families` and `persons`
5. **Schema updates**: Family and Person get `belongs_to :organization`
6. **Context updates**: All query functions in Families, People, Galleries, Relationships, Comments, Kinship scoped by org where needed
7. **Router**: All routes move under `/org/:org_id` scope
8. **LiveView updates**: All LiveViews receive `org_id` from params, pass it through navigation links
9. **Seeds**: Create default organization, assign all seed data to it
10. **Layout**: Update header nav to be org-aware

## Open Questions

- None — straightforward tenant scoping.

## Next Steps

→ `/ce:plan` for implementation details
