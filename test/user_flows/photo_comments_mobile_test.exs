defmodule Web.UserFlows.PhotoCommentsMobileTest do
  @moduledoc """
  E2E tests for photo comments on mobile viewports.

  ## Scenarios

  ### Tapping a comment highlights it and shows edit/delete actions
  Given a logged-in admin on mobile
  And a comment on a photo
  When they open the lightbox and comments panel
  And tap the comment
  Then the comment is highlighted
  And edit/delete action buttons appear inline under the comment text
  """
  use Web.E2ECase

  # Force a mobile viewport so the mobile layout (md:hidden) is active
  # and the desktop layout (hidden md:flex) is hidden.
  @moduletag browser_context_opts: [viewport: %{width: 414, height: 896}]

  setup do
    family = insert(:family, name: "Comments Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg", status: "processed")
      |> ensure_photo_file()

    %{family: family, org: org, gallery: gallery, photo: photo}
  end

  test "tapping a comment on mobile selects it and reveals action buttons", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn = log_in_e2e(conn)

    # Create a comment authored by the current logged-in admin so edit is allowed
    # We create it via direct insertion using the admin account that log_in_e2e
    # will create. Since log_in_e2e creates a new admin account each call, we
    # need to create the comment after login with the same account_id.
    account = Ancestry.Repo.one!(Ancestry.Identity.Account)

    {:ok, _comment} =
      Ancestry.Comments.create_photo_comment(photo.id, account.id, %{text: "My comment"})

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # Before tapping, no action buttons should be visible on mobile
    refute_has(conn, "#{test_id("mobile-comment-list")} button[phx-click='edit_comment']")

    # Tap the mobile comment — this should select it and reveal the actions
    conn =
      conn
      |> click(test_id("mobile-comment-list"))

    # After tap, the edit and delete buttons should be visible
    conn
    |> assert_has("#{test_id("mobile-comment-list")} button[phx-click='edit_comment']")
    |> assert_has("#{test_id("mobile-comment-list")} button[phx-click='delete_comment']")
  end
end
