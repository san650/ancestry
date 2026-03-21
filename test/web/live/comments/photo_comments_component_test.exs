defmodule Web.Comments.PhotoCommentsComponentTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ancestry.Comments
  alias Ancestry.Families
  alias Ancestry.Galleries

  describe "rendering" do
    test "shows existing comments for a photo", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, _} = Comments.create_photo_comment(%{text: "Great shot!", photo_id: photo.id})
      {:ok, _} = Comments.create_photo_comment(%{text: "Love it", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel")
      assert has_element?(view, "#photo-comments-panel", "Great shot!")
      assert has_element?(view, "#photo-comments-panel", "Love it")
    end

    test "shows empty state when no comments", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel")
      assert has_element?(view, "#comments-empty")
    end
  end

  describe "creating comments" do
    test "submitting the form creates a comment", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      view
      |> form("#new-comment-form", comment: %{text: "Beautiful photo!"})
      |> render_submit()

      # The PubSub broadcast from create_photo_comment is delivered to the LiveView
      # process which forwards it to the component via send_update. A second render
      # flushes the deferred send_update.
      render(view)
      assert has_element?(view, "#photo-comments-panel", "Beautiful photo!")
    end

    test "submitting empty text does not create a comment", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      view
      |> form("#new-comment-form", comment: %{text: ""})
      |> render_submit()

      # Comment should not appear; empty state should remain
      assert has_element?(view, "#comments-empty")
    end
  end

  describe "editing comments" do
    test "edit and save updates the comment", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()
      {:ok, comment} = Comments.create_photo_comment(%{text: "Original", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Original")

      view
      |> element("[phx-click='edit_comment'][phx-value-id='#{comment.id}']")
      |> render_click()

      assert has_element?(view, "#edit-comment-#{comment.id}")

      view
      |> form("#edit-comment-#{comment.id}", comment: %{text: "Edited text"})
      |> render_submit()

      # The PubSub broadcast triggers send_update; render to flush it
      render(view)
      assert has_element?(view, "#photo-comments-panel", "Edited text")
      refute has_element?(view, "#edit-comment-#{comment.id}")
    end

    test "cancel edit hides the edit form", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()
      {:ok, comment} = Comments.create_photo_comment(%{text: "Original", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      view
      |> element("[phx-click='edit_comment'][phx-value-id='#{comment.id}']")
      |> render_click()

      assert has_element?(view, "#edit-comment-#{comment.id}")

      view |> element("[phx-click='cancel_edit']") |> render_click()
      refute has_element?(view, "#edit-comment-#{comment.id}")
      assert has_element?(view, "#photo-comments-panel", "Original")
    end
  end

  describe "deleting comments" do
    test "clicking delete removes the comment", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()
      {:ok, comment} = Comments.create_photo_comment(%{text: "Delete me", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Delete me")

      view
      |> element("[phx-click='delete_comment'][phx-value-id='#{comment.id}']")
      |> render_click()

      # The PubSub broadcast triggers send_update for stream_delete; render to flush
      render(view)
      refute has_element?(view, "#photo-comments-panel", "Delete me")
    end
  end

  describe "lightbox integration" do
    test "toggle button opens and closes comments panel", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()

      refute has_element?(view, "#photo-comments-panel")

      view |> element("#toggle-panel-btn") |> render_click()
      assert has_element?(view, "#photo-comments-panel")

      view |> element("#toggle-panel-btn") |> render_click()
      refute has_element?(view, "#photo-comments-panel")
    end

    test "closing lightbox closes comments panel", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel")

      view |> element("[phx-click='close_lightbox']") |> render_click()

      refute has_element?(view, "#lightbox")
      refute has_element?(view, "#photo-comments-panel")
    end

    test "navigating photos loads comments for the new photo", %{conn: conn} do
      {family, gallery, photo1, org} = setup_gallery_with_photo()
      photo2 = photo_fixture(gallery)

      {:ok, _} =
        Comments.create_photo_comment(%{text: "Comment on photo 1", photo_id: photo1.id})

      {:ok, _} =
        Comments.create_photo_comment(%{text: "Comment on photo 2", photo_id: photo2.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo1.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Comment on photo 1")
      refute has_element?(view, "#photo-comments-panel", "Comment on photo 2")

      view
      |> element("[phx-click='lightbox_select'][phx-value-id='#{photo2.id}']")
      |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Comment on photo 2")
      refute has_element?(view, "#photo-comments-panel", "Comment on photo 1")
    end

    test "navigating to photo with no comments shows empty state", %{conn: conn} do
      {family, gallery, photo1, org} = setup_gallery_with_photo()
      photo2 = photo_fixture(gallery)

      {:ok, _} =
        Comments.create_photo_comment(%{text: "Only on photo 1", photo_id: photo1.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo1.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Only on photo 1")

      view
      |> element("[phx-click='lightbox_select'][phx-value-id='#{photo2.id}']")
      |> render_click()

      refute has_element?(view, "#photo-comments-panel", "Only on photo 1")
      assert has_element?(view, "#comments-empty")
    end
  end

  describe "real-time updates" do
    test "receiving comment_created message adds comment to panel", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      # Simulate a PubSub broadcast by sending the message directly to the LiveView
      {:ok, comment} =
        Comments.create_photo_comment(%{text: "From another user", photo_id: photo.id})

      send(view.pid, {:comment_created, comment})

      # Render twice: once to process the handle_info (which calls send_update),
      # and once to process the deferred send_update
      render(view)
      assert has_element?(view, "#photo-comments-panel", "From another user")
    end

    test "receiving comment_updated message updates comment in panel", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()
      {:ok, comment} = Comments.create_photo_comment(%{text: "Before edit", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Before edit")

      {:ok, updated} = Comments.update_photo_comment(comment, %{text: "After edit"})

      send(view.pid, {:comment_updated, updated})
      render(view)
      assert has_element?(view, "#photo-comments-panel", "After edit")
    end

    test "receiving comment_deleted message removes comment from panel", %{conn: conn} do
      {family, gallery, photo, org} = setup_gallery_with_photo()
      {:ok, comment} = Comments.create_photo_comment(%{text: "Will vanish", photo_id: photo.id})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-panel-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel", "Will vanish")

      {:ok, _} = Comments.delete_photo_comment(comment)

      send(view.pid, {:comment_deleted, comment})
      render(view)
      refute has_element?(view, "#photo-comments-panel", "Will vanish")
    end
  end

  # -- Fixtures --

  defp setup_gallery_with_photo do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    family = family_fixture(org)
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)
    {family, gallery, photo, org}
  end

  defp family_fixture(org, attrs \\ %{}) do
    {:ok, family} =
      Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end

  defp gallery_fixture(family, attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery", family_id: family.id})
      |> Galleries.create_gallery()

    gallery
  end

  defp photo_fixture(gallery) do
    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/nonexistent.jpg",
        original_filename: "photo.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo} = Galleries.update_photo_processed(photo, "photo.jpg")
    photo
  end
end
