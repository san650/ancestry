# Remove Person Photo

## Problem

There is no way to remove a person's photo from the edit form. The current photo thumbnail is displayed but offers no removal action.

## Solution

Add a "Remove" link next to the current photo in the edit form. Clicking it clears the photo from the database and deletes the files on disk.

### Changes

**1. `Ancestry.People` context**
- Add `remove_photo/1` — clears `photo` and `photo_status` fields, deletes files on disk via existing `cleanup_person_files/1`

**2. Person form template (`person_form_component.html.heex`)**
- Add a "Remove" link next to the "Current photo" text, firing a `"remove_photo"` event

**3. `PersonLive.Show`**
- Add `handle_event("remove_photo", ...)` — calls `People.remove_photo/1`, updates `@person`, stays in edit mode

### NOT changing

- No confirmation modal (low-risk, photo can be re-uploaded immediately)
- No changes to Waffle uploader or Oban jobs
- No changes to PersonLive.New (no existing photo on create)
