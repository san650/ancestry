defmodule Web.GalleryLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Family.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery"})
    %{gallery: gallery}
  end

  test "shows gallery name and upload area", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert html =~ gallery.name
    assert html =~ "upload-area"
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
end
