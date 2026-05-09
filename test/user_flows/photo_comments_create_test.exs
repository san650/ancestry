defmodule Web.UserFlows.PhotoCommentsCreateTest do
  @moduledoc """
  Verifies that creating a photo comment dispatches through `Ancestry.Bus`,
  writes a row to `audit_log`, and surfaces validation errors without
  writing an audit row.

  ## Scenarios

  ### Bus-driven comment creation
  Given a logged-in account with access to a gallery and photo
  When the user opens the lightbox + comments panel
  And submits the new-comment form with valid text
  Then the comment appears in the list
  And an audit_log row is written for `Ancestry.Commands.AddCommentToPhoto`

  ### Validation error path
  Given the same setup
  When the user submits the form with empty text
  Then no comment is created
  And no audit_log row is written
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery, status: "processed")
    %{org: org, family: family, gallery: gallery, photo: photo}
  end

  test "creates a comment via Ancestry.Bus and writes an audit row", %{
    conn: conn,
    org: org,
    family: family,
    gallery: gallery,
    photo: photo
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-panel-btn") |> render_click()

    view
    |> form("#new-comment-form", comment: %{text: "Hello"})
    |> render_submit()

    render(view)
    assert has_element?(view, "#photo-comments-panel", "Hello")

    assert [comment] = Repo.all(PhotoComment)
    assert comment.text == "Hello"

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddCommentToPhoto"
    assert row.payload["text"] == "Hello"
    assert row.payload["photo_id"] == photo.id
  end

  test "shows validation error on empty submit and writes no audit row", %{
    conn: conn,
    org: org,
    family: family,
    gallery: gallery,
    photo: photo
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-panel-btn") |> render_click()

    view
    |> form("#new-comment-form", comment: %{text: ""})
    |> render_submit()

    assert has_element?(view, "#comments-empty")
    assert Repo.all(PhotoComment) == []
    assert Repo.all(Log) == []
  end
end
