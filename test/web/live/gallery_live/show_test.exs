defmodule Web.GalleryLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families
  alias Ancestry.Galleries

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})
    %{gallery: gallery, family: family}
  end

  test "shows gallery name and upload button", %{conn: conn, gallery: gallery, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")
    assert html =~ gallery.name
    assert html =~ "upload-btn"
  end

  test "shows empty state when no photos", %{conn: conn, gallery: gallery, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")
    assert html =~ "No photos yet"
  end

  test "toggles between masonry and uniform grid", %{conn: conn, gallery: gallery, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")
    assert has_element?(view, "#photo-grid.masonry-grid")
    view |> element("#layout-toggle") |> render_click()
    assert has_element?(view, "#photo-grid.uniform-grid")
  end

  test "activates and cancels selection mode", %{conn: conn, gallery: gallery, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")
    refute has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    assert has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    refute has_element?(view, "#selection-bar")
  end

  test "shows photo_processed message updates photo in grid", %{
    conn: conn,
    gallery: gallery,
    family: family
  } do
    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/x.jpg",
        original_filename: "x.jpg",
        content_type: "image/jpeg"
      })

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")
    assert has_element?(view, "#photos-#{photo.id}")

    {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
    send(view.pid, {:photo_processed, updated})
    assert has_element?(view, "#photos-#{photo.id}")
  end

  describe "upload modal" do
    test "uploading a file opens the modal and shows progress", %{
      conn: conn,
      gallery: gallery,
      family: family
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

      refute has_element?(view, "#upload-modal")

      photo =
        file_input(view, "#upload-form", :photos, [
          %{
            name: "photo1.jpg",
            content: File.read!("test/fixtures/test_image.jpg"),
            type: "image/jpeg"
          }
        ])

      render_upload(photo, "photo1.jpg")

      assert has_element?(view, "#upload-modal")
    end

    test "close_upload_modal closes the modal", %{
      conn: conn,
      gallery: gallery,
      family: family
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

      photo =
        file_input(view, "#upload-form", :photos, [
          %{
            name: "photo1.jpg",
            content: File.read!("test/fixtures/test_image.jpg"),
            type: "image/jpeg"
          }
        ])

      render_upload(photo, "photo1.jpg")

      assert has_element?(view, "#upload-modal")

      view |> element("#upload-modal-close") |> render_click()

      refute has_element?(view, "#upload-modal")
    end
  end
end
