defmodule Web.UserFlows.PhotoCommentsDeleteTest do
  @moduledoc """
  Verifies that deleting a photo comment dispatches through `Ancestry.Bus`,
  enforces the owner-or-admin record-level rule, and writes an audit row.

  ## Scenarios

  ### Owner delete
  Given a comment authored by the logged-in account
  When the user clicks the delete button
  Then the comment is removed
  And an audit_log row is written for `Ancestry.Commands.RemoveCommentFromPhoto`
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
    comment = insert(:photo_comment, photo: photo, account: account, text: "Doomed")
    %{org: org, family: family, gallery: gallery, photo: photo, comment: comment}
  end

  test "owner deletes their comment via the bus and an audit row is written", %{
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

    assert has_element?(view, "#photo-comments-panel", "Doomed")

    view
    |> element(
      "[data-testid='desktop-comment-list'] [phx-click='delete_comment'][phx-value-id='#{comment.id}']"
    )
    |> render_click()

    render(view)
    refute has_element?(view, "#photo-comments-panel", "Doomed")

    assert is_nil(Repo.get(PhotoComment, comment.id))

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.RemoveCommentFromPhoto"
    assert row.payload["arguments"]["photo_comment_id"] == comment.id
  end
end
