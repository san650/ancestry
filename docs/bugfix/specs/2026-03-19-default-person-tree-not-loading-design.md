# Bug: Default person tree doesn't load after saving

## Problem

After setting a default person in the Edit Family modal and saving, the tree view remains empty. The default person's tree only renders after navigating away and back.

## Root Cause

The `save` event handler in `FamilyLive.Show` persists the default person and closes the modal, but doesn't update `@focus_person` or `@tree` assigns. The default person fallback logic only runs in `handle_params/3`, which is only called on mount or URL changes — not after event handlers.

## Fix

In `handle_event("save", ...)`, after persisting the default person selection, also update `@focus_person` and `@tree` based on the new default:

- If a default person was selected: find them in `@people`, build their tree, assign both
- If default was cleared ("None"): set both to `nil`

## Test Update

Update the E2E test to verify the tree renders **immediately** after saving the default person, without needing to navigate away and back.
