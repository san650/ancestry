# Link People in Photos — Design

## Summary

Allow users to tag people in gallery photos by clicking on the photo to place a marker, then selecting a person from a search popover. Tagged people are displayed as circles overlaid on the photo and listed in the right panel.

## Decisions

- **Scope:** Any person in the system can be tagged (not limited to family members)
- **Circle size:** Fixed (~40px), no drag-to-resize
- **Remove tags:** Via X button in the right panel list only
- **Right panel:** Stacked sections — People (top), Comments (bottom)
- **Person selector:** Popover near the click point on the photo
- **Data model:** Join table `photo_people` with percentage-based coordinates

## Data Model

### New table: `photo_people`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| photo_id | references(:photos) | FK, on_delete: :delete_all |
| person_id | references(:persons) | FK, on_delete: :delete_all |
| x | float | 0.0–1.0, percentage of image width |
| y | float | 0.0–1.0, percentage of image height |
| inserted_at | utc_datetime | timestamp |

Unique constraint on `[:photo_id, :person_id]` — one tag per person per photo.

### New schema: `Ancestry.Galleries.PhotoPerson`

- `belongs_to :photo`
- `belongs_to :person`
- Fields: `x`, `y` (floats)

### Association changes

- `Photo` adds `has_many :photo_people` and `has_many :people, through: [:photo_people, :person]`
- `Person` adds `has_many :photo_people` and `has_many :photos, through: [:photo_people, :photo]`

### New context functions in `Ancestry.Galleries`

- `tag_person_in_photo(photo_id, person_id, x, y)` — insert
- `untag_person_from_photo(photo_id, person_id)` — delete
- `list_photo_people(photo_id)` — returns photo_people with preloaded person, ordered by inserted_at

## Interaction Flow

### Tagging a person

1. User clicks on the photo image in the lightbox
2. Colocated JS hook (`.PhotoTagger`) captures click coordinates as percentages: `click_x / image.naturalWidth`, `click_y / image.naturalHeight`
3. Popover appears near the click point with a search input
4. User types — debounced search calls `search_all_people(query, nil)` via `pushEvent`
5. Results render in the popover (person thumbnail + display name)
6. User selects a person — hook sends `tag_person` event with `{x, y, person_id}`
7. Server inserts `PhotoPerson`, returns updated list
8. Popover closes, circle appears, person added to right panel list
9. Click-away or Escape dismisses the popover without tagging

### Circle rendering

- Absolutely positioned divs overlaid on the photo
- Fixed ~40px diameter
- Transparent fill, dotted border, dim color (`border-2 border-dashed border-white/50 rounded-full`)
- On hover: tooltip with person name below the circle

### Coordinates

Stored as 0.0–1.0 percentages. Displayed via `left: x * 100%`, `top: y * 100%` on the image container. Resolution-independent.

### Hover interactions

- Hover person in right panel list — highlights corresponding circle on photo (brighter border, pulse)
- Hover circle on photo — shows person name tooltip

## Right Panel Generalization

### Current state

Right panel is `PhotoCommentsComponent`, toggled by `@comments_open`.

### New structure

- Rename toggle: `@panel_open` instead of `@comments_open`
- Panel becomes a container with two stacked sections:
  1. **People section** (top): header with count badge, list of tagged people (thumbnail + name + X remove button)
  2. **Comments section** (bottom): existing `PhotoCommentsComponent` unchanged
- Divider (`border-t`) between sections
- Toolbar button updated from "Comments" to a general panel icon

### Hover from sidebar

Hovering a person row in the panel triggers a JS event that highlights the corresponding circle on the photo. Mouse leave removes the highlight.

## Testing

### Context tests

- `tag_person_in_photo/4` — happy path, duplicate constraint, invalid references
- `untag_person_from_photo/2` — happy path, no-op when not tagged
- `list_photo_people/1` — returns preloaded people, ordered by inserted_at

### E2E test (`test/user_flows/link_people_in_photos_test.exs`)

```
Given a family with a gallery containing a processed photo
And two existing people in the system

When the user opens the gallery and clicks on the photo
Then the lightbox opens

When the user clicks on the photo image
Then a popover appears with a search input

When the user searches for a person name
Then matching results appear

When the user selects a person from the results
Then a circle appears on the photo at the clicked position
And the person appears in the right panel people list

When the user hovers the person in the right panel
Then the circle on the photo is highlighted

When the user clicks X next to the person in the right panel
Then the person is removed from the list
And the circle disappears from the photo

When the user tags a second person at a different position
Then both circles are visible and both people listed
```
