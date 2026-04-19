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
- `<a>` tags default to `cursor: pointer`, so no extra class needed.

### No Server-Side Changes

`@current_scope` is already passed to the lightbox component. No new events, assigns, or context functions required.

## Testing

Add an E2E test in `test/user_flows/` that:

1. Creates a gallery with a processed photo and a person
2. Tags the person in the photo
3. Opens the lightbox, opens the info panel
4. Clicks the person name in the panel
5. Asserts navigation to the person show page

## Files Changed

- `lib/web/components/photo_gallery.ex` — template change in `lightbox/1`
- `test/user_flows/photo_to_person_navigation_test.exs` — new E2E test
