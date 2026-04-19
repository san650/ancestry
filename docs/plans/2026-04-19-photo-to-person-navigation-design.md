# Photo-to-Person Navigation

## Summary

Make tagged person names/avatars in the lightbox info panel clickable links that navigate to the person show page (`/org/:org_id/people/:person_id`).

## Current State

The lightbox right panel shows tagged people as rows with avatar + name + untag button. The rows have a `PersonHighlight` hook for hover-highlighting tags on the photo, but **no navigation**. Clicking a person's name does nothing.

## Design

### Change

In `lib/web/components/photo_gallery.ex`, inside the `lightbox/1` component's people list (the `for pp <- @photo_people` loop):

- Wrap the avatar + name in a `<.link navigate={~p"/org/#{@current_scope.organization.id}/people/#{pp.person_id}"}>`.
- The untag `<button>` stays outside the link.
- The outer `<div>` with `PersonHighlight` hook is unaffected — hover still highlights the tag on the photo.

### Styling

- The link inherits existing text style (`text-sm text-white/85`).
- Add `hover:text-white` for a subtle hover cue.
- Add `focus-visible:text-white` for keyboard accessibility on the dark background.
- `<a>` tags default to `cursor: pointer`, so no extra class needed.

### Scope

The `lightbox/1` component is shared by both `GalleryLive.Show` and `PersonLive.Show` (via `PhotoInteractions`). This change applies to both contexts — clicking a tagged person navigates to their page regardless of which LiveView the lightbox was opened from.

### No Server-Side Changes

`@current_scope` is already passed to the lightbox component. No new events, assigns, or context functions required.

## Testing

Add an E2E test in `test/user_flows/` that:

1. Creates a gallery with a processed photo and two tagged people
2. Opens the lightbox, opens the info panel
3. Asserts each person link has the correct `href` (`/org/:org_id/people/:person_id`)
4. Clicks a person name in the panel
5. Asserts navigation to the correct person show page

## Files Changed

- `lib/web/components/photo_gallery.ex` — template change in `lightbox/1`
- `test/user_flows/photo_to_person_navigation_test.exs` — new E2E test
