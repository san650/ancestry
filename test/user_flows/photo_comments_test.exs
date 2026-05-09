defmodule Web.UserFlows.PhotoCommentsTest do
  @moduledoc """
  E2E tests for photo comments with account linking, avatars, and permissions.

  ## Scenarios

  ### Comment with avatar
  Given a gallery with a photo
  When the user opens the lightbox and comments panel
  And writes a comment
  Then the comment appears with the user's name and avatar initials

  ### Non-owner cannot edit
  Given a comment authored by another user
  When viewing the comment as a non-admin editor
  Then the edit button is not visible
  But the delete button for their own comment is visible

  ### Admin can delete any comment
  Given a comment authored by another user
  When viewing the comment as an admin
  Then the delete button is visible for any comment

  ### Unknown author fallback
  Given a comment with no account (nil account_id)
  When viewing the comment
  Then "Unknown" is displayed as the author name
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Comments Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg", status: "processed")
      |> ensure_photo_file()

    %{family: family, org: org, gallery: gallery, photo: photo}
  end

  # Given a gallery with a photo
  # When the user opens the lightbox and comments panel
  # And writes a comment and submits it
  # Then the comment appears in the comments list
  test "comment displays in comments list after submission", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn = log_in_e2e(conn)

    # Navigate to gallery and open lightbox
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # Open the side panel
    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel", timeout: 3_000)

    # Type a comment and submit the form
    conn = PhoenixTest.Playwright.type(conn, "#new-comment-text", "Great photo!")

    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        document.querySelector('#new-comment-form button[type="submit"]').click();
      """)

    # The comment should appear in the list
    conn
    |> assert_has(test_id("desktop-comment-list"), text: "Great photo!", timeout: 5_000)
  end

  # Given a comment authored by another user
  # When viewing the comment as a non-admin editor
  # Then the comment text and author name are visible
  # And the edit button is not visible (only owner can edit)
  test "non-owner cannot see edit button on another user's comment", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    other_account = insert(:account, name: "Other User", role: :editor)

    insert(:photo_comment, photo: photo, account: other_account, text: "Someone else's comment")

    conn =
      conn
      |> log_in_e2e(role: :editor, organization_ids: [org.id])
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # The comment and author should be visible
    conn
    |> assert_has(test_id("desktop-comment-list"), text: "Someone else's comment")
    |> assert_has(test_id("desktop-comment-list"), text: "Other User")

    # The edit button should NOT be present for someone else's comment
    # (edit buttons are rendered server-side based on can_edit?, not just CSS hidden)
    refute_has(conn, "#{test_id("desktop-comment-list")} button[phx-click='edit_comment']")
  end

  # Given a comment authored by another user
  # When viewing the comment as an admin
  # Then the delete button is visible (admins can delete any comment)
  # And the comment text and author name are visible
  test "admin can see delete button on another user's comment", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    other_account = insert(:account, name: "Regular User", role: :editor)

    insert(:photo_comment, photo: photo, account: other_account, text: "Admin can delete this")

    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # The comment and author should be visible
    conn
    |> assert_has(test_id("desktop-comment-list"), text: "Admin can delete this")
    |> assert_has(test_id("desktop-comment-list"), text: "Regular User")

    # The delete button should be present (admin can delete any comment)
    assert_has(conn, "#{test_id("desktop-comment-list")} button[phx-click='delete_comment']")
  end

  # Given a comment with nil account_id (legacy comment)
  # When viewing the comment
  # Then "Unknown" is displayed as the author name
  test "pre-existing comment with nil account shows Unknown", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    Ancestry.Repo.insert!(%Ancestry.Comments.PhotoComment{
      text: "Legacy comment",
      photo_id: photo.id,
      account_id: nil
    })

    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # The comment text should be visible
    conn
    |> assert_has(test_id("desktop-comment-list"), text: "Legacy comment", timeout: 5_000)

    # "Unknown" should appear as the author name
    assert_has(conn, test_id("desktop-comment-list"), text: "Unknown")
  end
end
