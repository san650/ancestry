# Photo-to-Person Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tagged person names/avatars in the lightbox info panel clickable links that navigate to the person show page.

**Architecture:** Template-only change in the shared `lightbox/1` component. Wrap the avatar + name in a `<.link navigate=...>` using `@current_scope.organization.id` and `pp.person_id`. No server-side changes needed.

**Tech Stack:** Phoenix LiveView, HEEx templates

**Spec:** `docs/plans/2026-04-19-photo-to-person-navigation-design.md`

---

### Task 1: Add navigate link to person rows in lightbox

**Files:**
- Modify: `lib/web/components/photo_gallery.ex:261-295`

- [ ] **Step 1: Wrap avatar + name in a `<.link>`**

In `lib/web/components/photo_gallery.ex`, inside the `for pp <- @photo_people` loop, wrap the avatar (the `<img>` / fallback `<div>`) and the name `<span>` in a `<.link>`. The untag `<button>` stays outside the link.

Replace lines 268-285 (the avatar + name portion inside the person row `<div>`):

```heex
<.link
  navigate={~p"/org/#{@current_scope.organization.id}/people/#{pp.person_id}"}
  class="flex items-center gap-3 lg:gap-2 flex-1 min-w-0 hover:text-white focus-visible:text-white transition-colors"
>
  <%= if pp.person.photo && pp.person.photo_status == "processed" do %>
    <img
      src={
        Ancestry.Uploaders.PersonPhoto.url(
          {pp.person.photo, pp.person},
          :thumbnail
        )
      }
      class="w-7 h-7 lg:w-6 lg:h-6 rounded-full object-cover shrink-0"
    />
  <% else %>
    <div class="w-7 h-7 lg:w-6 lg:h-6 rounded-full bg-white/[0.10] flex items-center justify-center shrink-0">
      <.icon name="hero-user" class="w-4 h-4 lg:w-3.5 lg:h-3.5 text-white/40" />
    </div>
  <% end %>
  <span class="text-sm text-white/85 truncate flex-1">
    {Ancestry.People.Person.display_name(pp.person)}
  </span>
</.link>
```

The outer `<div>` with `PersonHighlight` hook and the untag `<button>` remain unchanged.

- [ ] **Step 2: Verify the app compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with zero warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/web/components/photo_gallery.ex
git commit -m "Add navigate link from tagged person to person show page"
```

---

### Task 2: Add E2E test for photo-to-person navigation

**Files:**
- Create: `test/user_flows/photo_to_person_navigation_test.exs`

- [ ] **Step 1: Write the E2E test**

```elixir
defmodule Web.UserFlows.PhotoToPersonNavigationTest do
  use Web.E2ECase

  # Navigate from photo lightbox to person show page
  #
  # Given a gallery with a processed photo and two tagged people
  # When the user opens the lightbox and the info panel
  # Then each person row has a link to the person show page
  #
  # When the user clicks a person name
  # Then the app navigates to that person's show page

  setup do
    family = insert(:family, name: "Navigation Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg")
      |> ensure_photo_file()

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Nav",
        organization: family.organization
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Nav",
        organization: family.organization
      )

    {:ok, _} = Ancestry.Galleries.tag_person_in_photo(photo.id, alice.id, 0.3, 0.4)
    {:ok, _} = Ancestry.Galleries.tag_person_in_photo(photo.id, bob.id, 0.6, 0.7)

    %{family: family, gallery: gallery, photo: photo, alice: alice, bob: bob, org: org}
  end

  test "clicking a tagged person navigates to person show page", %{
    conn: conn,
    family: family,
    gallery: gallery,
    photo: photo,
    alice: alice,
    bob: bob,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Navigate to the gallery show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # Click the photo to open lightbox
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # Open the side panel
    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-person-list")

    # Both tagged people should be visible
    conn =
      conn
      |> assert_has("#photo-person-list", text: "Alice Nav")
      |> assert_has("#photo-person-list", text: "Bob Nav")

    # Verify each person has a link with the correct href
    conn =
      conn
      |> assert_has(
        "#photo-person-list a[href='/org/#{org.id}/people/#{alice.id}']",
        text: "Alice Nav"
      )
      |> assert_has(
        "#photo-person-list a[href='/org/#{org.id}/people/#{bob.id}']",
        text: "Bob Nav"
      )

    # Click Alice's name to navigate to her person show page
    conn =
      conn
      |> click("#photo-person-list a[href='/org/#{org.id}/people/#{alice.id}']")

    # Should be on Alice's person show page
    conn
    |> assert_has("h1", text: "Alice Nav")
  end
end
```

- [ ] **Step 2: Run the test**

Run: `mix test test/user_flows/photo_to_person_navigation_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/photo_to_person_navigation_test.exs
git commit -m "Add E2E test for photo-to-person navigation"
```

---

### Task 3: Final verification

- [ ] **Step 1: Run precommit checks**

Run: `mix precommit`
Expected: all checks pass (compile, format, tests).
