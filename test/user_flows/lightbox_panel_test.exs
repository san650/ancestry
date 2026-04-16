defmodule Web.UserFlows.LightboxPanelTest do
  @moduledoc """
  E2E tests for the lightbox side panel structure (People + Comments cards).

  ## Scenarios

  ### Panel reveals People and Comments cards
  Given a logged-in admin with a processed photo
  When they open the lightbox and toggle the info panel
  Then both the people-card and comments-card are visible
  And both show their empty-state copy

  ### Adding a comment dismisses the comments empty state
  Given the panel open with no comments
  When the user submits a new comment
  Then the empty state disappears
  And the comment appears in the list
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Lightbox Panel Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg", status: "processed")
      |> ensure_photo_file()

    %{family: family, org: org, gallery: gallery, photo: photo}
  end

  test "panel reveals People and Comments cards with empty states", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")

    # NOTE on dual-responsive layouts (see docs/learnings.jsonl#playwright-dual-responsive-layout):
    # The People-card empty state renders TWO spans in the DOM — one lg:hidden,
    # one hidden lg:inline. At the default 1280px viewport, only the desktop copy
    # ("Click on the photo to tag people") is visible. Asserting on that exact
    # desktop string is safe; if a future maintainer switches to a mobile viewport,
    # they must also flip the assertion to "No people tagged yet."
    conn
    |> assert_has(test_id("lightbox-people-card"))
    |> assert_has(test_id("lightbox-comments-card"))
    |> assert_has(test_id("lightbox-people-card"), text: "Click on the photo to tag people")
    |> assert_has(test_id("lightbox-comments-card"), text: "No comments yet")
  end

  test "adding a comment dismisses the empty state", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has(test_id("lightbox-comments-card"), text: "No comments yet")

    # Submit a new comment via the composer form. The textarea has no <label>
    # element — it has only a placeholder — so PhoenixTest.fill_in/3 (which
    # takes a label) does not apply. Use Playwright.type/3 with a CSS selector
    # (matches the pattern in test/user_flows/photo_comments_test.exs).
    conn = PhoenixTest.Playwright.type(conn, "#new-comment-text", "Hello from the test")

    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        document.querySelector('#new-comment-form button[type="submit"]').click();
      """)

    conn
    |> assert_has(test_id("desktop-comment-list"), text: "Hello from the test", timeout: 5_000)
    |> refute_has(test_id("lightbox-comments-card"), text: "No comments yet")
  end
end
