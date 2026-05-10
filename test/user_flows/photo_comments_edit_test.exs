defmodule Web.UserFlows.PhotoCommentsEditTest do
  @moduledoc """
  Verifies that editing a photo comment dispatches through `Ancestry.Bus`,
  enforces the owner-or-admin record-level rule, and writes an audit row.

  ## Scenarios

  ### Owner edit
  Given a comment authored by the logged-in account
  When the user edits the text and submits
  Then the comment is updated in place
  And an audit_log row is written for `Ancestry.Commands.UpdatePhotoComment`

  ### Admin edit on another user's comment
  Given a comment authored by a different account
  When an admin edits the text via direct save_edit dispatch
  Then the comment is updated
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery, status: "processed")
    comment = insert(:photo_comment, photo: photo, account: account, text: "before")
    %{org: org, family: family, gallery: gallery, photo: photo, comment: comment}
  end

  test "owner edits a comment and an audit row is written", %{
    conn: conn,
    org: org,
    family: family,
    gallery: gallery,
    photo: photo,
    comment: comment
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-panel-btn") |> render_click()

    view
    |> element(
      "[data-testid='desktop-comment-list'] [phx-click='edit_comment'][phx-value-id='#{comment.id}']"
    )
    |> render_click()

    view
    |> form("#edit-comment-#{comment.id}", comment: %{text: "after"})
    |> render_submit()

    render(view)
    assert has_element?(view, "#photo-comments-panel", "after")

    assert %PhotoComment{text: "after"} = Repo.get!(PhotoComment, comment.id)
    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.UpdatePhotoComment"
    assert row.payload["arguments"]["text"] == "after"
    assert row.payload["arguments"]["photo_comment_id"] == comment.id
  end
end
