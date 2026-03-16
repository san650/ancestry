# Bugfix: person_card navigation hijacks modal selection

**Date:** 2026-03-16
**Status:** Approved

## Bug

When adding a parent to a person, the modal shows search results. Clicking a result navigates to that person's detail page instead of selecting them. The parent association is never created.

## Root Cause

The `person_card` component wraps its content in `<.link navigate={~p"/families/#{@family.id}/members/#{@person.id}"}>`. In the search results modal, this component is nested inside a `<button phx-click="select_person">`. The `<.link navigate>` fires client-side navigation before the `phx-click` event reaches the server.

## Fix

Split `person_card` into a pure presentation component (no click behavior). Each call site wraps it with the appropriate interaction element.

### person_card changes

Remove the `<.link navigate>` wrapper. The component renders a `<div>` with avatar, name, dates, and styling. The `highlighted` attr stays for visual emphasis.

### Call site updates

| Location | Context | Wrapper |
|----------|---------|---------|
| Line 319 | Current person in partner group (highlighted) | No link (current person) |
| Line 324 | Partner card | `<.link navigate>` to partner |
| Line 396 | Child in partner group | `<.link navigate>` to child |
| Line 423 | Solo child | `<.link navigate>` to child |
| Line 460 | Parent card | `<.link navigate>` to parent |
| Line 524 | Current person in siblings (highlighted) | No link (current person) |
| Line 528 | Sibling | `<.link navigate>` to sibling |
| Line 642 | Search result in modal | `<button phx-click="select_person">` |
| Line 658 | Selected person confirmation | No link (display only) |

### Testing

Existing relationship tests must continue to pass. Verify that clicking a search result in the modal triggers `select_person` and does not navigate away.
