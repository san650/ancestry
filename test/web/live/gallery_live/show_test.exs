defmodule Web.GalleryLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Family.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery"})
    %{gallery: gallery}
  end

  test "shows gallery name and upload button", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert html =~ gallery.name
    assert html =~ "upload-btn"
  end

  test "shows empty state when no photos", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert html =~ "No photos yet"
  end

  test "toggles between masonry and uniform grid", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert has_element?(view, "#photo-grid.masonry-grid")
    view |> element("#layout-toggle") |> render_click()
    assert has_element?(view, "#photo-grid.uniform-grid")
  end

  test "activates and cancels selection mode", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    refute has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    assert has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    refute has_element?(view, "#selection-bar")
  end

  test "shows photo_processed message updates photo in grid", %{conn: conn, gallery: gallery} do
    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/x.jpg",
        original_filename: "x.jpg",
        content_type: "image/jpeg"
      })

    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert has_element?(view, "#photos-#{photo.id}")

    {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
    send(view.pid, {:photo_processed, updated})
    assert has_element?(view, "#photos-#{photo.id}")
  end

  describe "upload modal" do
    test "queue_files event opens upload modal with file list", %{conn: conn, gallery: gallery} do
      {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

      refute has_element?(view, "#upload-modal")

      render_hook(view, "queue_files", %{
        "files" => [
          %{"name" => "photo1.jpg", "size" => 1024},
          %{"name" => "photo2.jpg", "size" => 2048}
        ]
      })

      assert has_element?(view, "#upload-modal")
      assert has_element?(view, "#upload-modal", "photo1.jpg")
      assert has_element?(view, "#upload-modal", "photo2.jpg")
    end

    test "close_upload_modal closes the modal when status is done", %{
      conn: conn,
      gallery: gallery
    } do
      {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

      render_hook(view, "queue_files", %{
        "files" => [%{"name" => "photo1.jpg", "size" => 1024}]
      })

      assert has_element?(view, "#upload-modal")

      # Simulate done state by calling close (in production this fires after all done)
      render_hook(view, "close_upload_modal", %{})

      refute has_element?(view, "#upload-modal")
    end

    test "cancel_upload_modal shows confirmation when files are pending", %{
      conn: conn,
      gallery: gallery
    } do
      {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

      render_hook(view, "queue_files", %{
        "files" => [
          %{"name" => "photo1.jpg", "size" => 1024},
          %{"name" => "photo2.jpg", "size" => 2048}
        ]
      })

      render_hook(view, "cancel_upload_modal", %{})

      assert has_element?(view, "#upload-cancel-confirm")
    end

    test "confirm_cancel_upload closes modal and clears queue", %{conn: conn, gallery: gallery} do
      {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

      render_hook(view, "queue_files", %{
        "files" => [%{"name" => "photo1.jpg", "size" => 1024}]
      })

      render_hook(view, "cancel_upload_modal", %{})
      render_hook(view, "confirm_cancel_upload", %{})

      refute has_element?(view, "#upload-modal")
      refute has_element?(view, "#upload-cancel-confirm")
    end
  end
end
