# Family Members (Persons) — Design

## Overview

Add the ability to store family members (persons) in the Ancestry app. A person has one structured name, a list of simple alternate names, partial birth/death dates, gender, living status, and a profile photo. Persons relate to families via a many-to-many join table, allowing a person to belong to multiple families.

## Data Model

### `persons` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` (auto PK) | Standard Ecto id |
| `given_name` | `text` | Current given name |
| `surname` | `text` | Current surname |
| `given_name_at_birth` | `text` | Birth given name |
| `surname_at_birth` | `text` | Birth surname |
| `nickname` | `text` | |
| `title` | `text` | e.g. "Dr.", "Sir" |
| `suffix` | `text` | e.g. "Jr.", "III" |
| `alternate_names` | `text[]` | Simple text aliases (aka) |
| `birth_day` | `integer` | 1-31, nullable |
| `birth_month` | `integer` | 1-12, nullable |
| `birth_year` | `integer` | nullable |
| `death_day` | `integer` | 1-31, nullable |
| `death_month` | `integer` | 1-12, nullable |
| `death_year` | `integer` | nullable |
| `living` | `text` | "yes", "no", "unknown" — default "yes" |
| `gender` | `text` | "female", "male", "other" — stored as text for extensibility |
| `photo` | Waffle attachment | Profile photo (original + thumbnail via Oban) |
| `photo_status` | `text` | "pending", "processed", "failed" |
| `timestamps` | | `inserted_at`, `updated_at` |

Display name is derived: `"#{given_name} #{surname}"` — not stored.

### `family_members` join table

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` | Standard PK |
| `family_id` | `references :families` | |
| `person_id` | `references :persons` | |
| `timestamps` | | |
| | unique index | on `[:family_id, :person_id]` |

Intentionally simple — can hold relationship data (role, type) when family relationships are added later.

## Module Structure

### Business logic

```
lib/ancestry/
  people.ex                             # People context — CRUD, search, family membership
  people/
    person.ex                           # Person schema (many-to-many families)
    family_member.ex                    # Join schema for family_members table
  uploaders/
    person_photo.ex                     # Waffle uploader — :original + :thumbnail
  workers/
    process_person_photo_job.ex         # Oban job for person photo processing
```

### Web layer

```
lib/web/
  live/
    person_live/
      index.ex                          # List persons for a family, link existing person
      show.ex                           # Person detail/edit
      new.ex                            # Create new person form
```

### Context API (`Ancestry.People`)

- `list_people_for_family(family_id)` — persons belonging to a family
- `get_person!(id)` — fetch with preloaded families
- `create_person(family, attrs)` — create and add to family
- `update_person(person, attrs)` — update person fields
- `delete_person(person)` — remove person + cleanup files
- `add_to_family(person, family)` — link existing person to a family
- `remove_from_family(person, family)` — unlink person from a family
- `search_people(query)` — search by name for the "link existing" feature
- `change_person(person, attrs)` — return changeset for forms

## Routes

Nested under families:

```
/families/:family_id/members              # PersonLive.Index — list family members
/families/:family_id/members/new          # PersonLive.New — create new person
/families/:family_id/members/:id          # PersonLive.Show — view/edit person
```

## Photo Processing

Follows the existing pattern (gallery photos, family covers):

1. User uploads photo via LiveView `allow_upload` (single file)
2. Temp file copied to `priv/static/uploads/originals/{uuid}/photo.ext`
3. `ProcessPersonPhotoJob` Oban job inserted (queue: `:photos`)
4. Job produces `:original` and `:thumbnail` via Waffle/ImageMagick, stored at `priv/static/uploads/people/{person_id}/`
5. On completion/failure, broadcasts `{:person_photo_processed, person}` or `{:person_photo_failed, person}` over PubSub topic `"person:{id}"`
6. `PersonLive.Show` subscribes and updates UI

## Search / Link Existing Person

- "Link Existing" on members index opens a search interface
- `phx-change` live filtering across `given_name`, `surname`, `nickname`, `alternate_names`
- Results show display name, photo thumbnail, and current families
- Excludes persons already in the current family
- Clicking a result calls `People.add_to_family/2` and returns to members index

## UI Flow

**Family Show page** — "Members" section/link navigating to members index.

**Members Index** — Grid/list of members with display name, photo thumbnail, birth year. "Add Member" and "Link Existing" buttons.

**New Member** — Form with name fields, date fields (day/month/year dropdowns), gender select, living status select, photo upload.

**Member Show** — Full person details, photo, edit functionality, list of families this person belongs to, ability to remove from current family.

## Design Decisions

- **Flat name columns** over embedded/separate table — one structured name per person, simple and queryable
- **Many-to-many** via join table — persons can belong to multiple families
- **Join table kept simple** — ready for relationship data later without schema changes
- **Living status independent** of death date — user controls it manually
- **Gender as text** — extensible without migrations
- **Partial dates** — day, month, year all independently optional
- **Display name derived** — `given_name + surname`, not stored
