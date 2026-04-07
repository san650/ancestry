# User flow tests

This folder contains end-to-end tests for the application's user flows. One file per flow, snake_case `.exs`. The focus is **user interactions**, not internal APIs.

## Choosing the test type

- Prefer e2e tests where possible.
- Use a LiveView test only when the flow doesn't depend on JavaScript that LiveView tests can't drive.
- Decide between adding a new test and extending an existing one based on how related the flows are. ~1000 lines per file is the soft cap.

## Conventions

- Every test starts with a `Given/When/Then` comment that mirrors the spec it covers.
- When a feature changes, update the comment **and** the test body together.
- Tests may overlap — that's fine if it makes sense from a user-flow perspective.

## Example specs

These are illustrative — copy the shape, not the literal text — when writing a new flow test.

<example>
Creating a new family

Given a system with no data
When the user clicks "New Family"
Then the "New Family" form is displayed.

When the user writes a name for the family
And selects a cover photo
And clicks "Create"
Then a new family is created
And the application navigates automatically to the family show page
And the empty state is shown

When the user clicks the navigate back arrow in the gallery
Then the grid with the list of families is shown

When the user clicks on the family shown in the grid
Then the user can see the family show page

Makes sure that all navigation and modals work as expected.
</example>

<example>
Edit family metadata

Given a family
When the user clicks on the family from the /families page
Then the user navigates to the family show page

When the user clicks "Edit" on the toolbar
Then a modal is shown to edit the family name

When the user enters a new family name in the modal
And clicks "Save"
Then the modal closes and the gallery show page is visible
And the gallery name is updated

Makes sure that all navigation and modals work as expected.
</example>

<example>
Delete family

Given a family with some people and galleries
When the user clicks on the family from the /families page
Then the user navigates to the family show page

When the user clicks "Delete" on the toolbar
Then a confirmation modal is shown

When the user clicks "Delete"
Then the gallery is deleted with all it's related galleries
And people is not deleted, just detached from the gallery
And the user is redirected to the /galleries page

Makes sure that all navigation and modals work as expected.
</example>

<example>
Creating people in a family

Given an existing family
When the user navigates to /families
And clicks on the existing family
Then the family show screen is shown
And the empty state can be seen

When the user clicks the add person button
Then the page navigates to the new member page

When the user fills the form with the user information
And uploads a photo for the user
And clicks "Create"
Then the page navigates to the family show page
And the new person is listed on the sidebar

Makes sure that all navigation and modals work as expected.
</example>

<example>
Linking people in a family

Given an existing family
And an existing person that's not associated to the family
When the user navigates to /families
And clicks on the existing family
Then the family show screen is shown
And the empty state can be seen

When the user clicks the link people
Then a modal is shown to search for an existing person

When the user search the existing user in the search form
Then the user appears as an option

When the user selects the person from the search form
Then the person is added to the family
And the page navigates to the family show page
And the new person is listed on the sidebar

Makes sure that all navigation and modals work as expected.
</example>
