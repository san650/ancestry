defmodule Web.GalleryLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families
  alias Ancestry.Galleries

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})
    %{gallery: gallery, family: family, org: org}
  end

  test "shows gallery name and upload button", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    assert html =~ gallery.name
    assert html =~ "upload-btn"
  end

  test "shows empty state when no photos", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    assert html =~ "No photos yet"
  end

  test "toggles between masonry and uniform grid", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    assert has_element?(view, "#photo-grid.masonry-grid")
    view |> element("#layout-toggle") |> render_click()
    assert has_element?(view, "#photo-grid.uniform-grid")
  end

  test "activates and cancels selection mode", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    refute has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    assert has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    refute has_element?(view, "#selection-bar")
  end

  test "shows photo_processed message updates photo in grid", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/x.jpg",
        original_filename: "x.jpg",
        content_type: "image/jpeg"
      })

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    assert has_element?(view, "#photos-#{photo.id}")

    {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
    send(view.pid, {:photo_processed, updated})
    assert has_element?(view, "#photos-#{photo.id}")
  end

  describe "photo selection and deletion" do
    setup %{gallery: gallery} do
      photos =
        for i <- 1..3 do
          {:ok, photo} =
            Galleries.create_photo(%{
              gallery_id: gallery.id,
              original_path: "/tmp/photo#{i}.jpg",
              original_filename: "photo#{i}.jpg",
              content_type: "image/jpeg"
            })

          photo
        end

      %{photos: photos}
    end

    test "clicking a photo in select mode toggles selection instead of opening lightbox",
         %{conn: conn, gallery: gallery, family: family, org: org, photos: [p1 | _]} do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      # Enter select mode
      view |> element("#select-btn") |> render_click()
      assert has_element?(view, "#selection-bar")

      # Click a photo — should select it, not open lightbox
      view |> element("#photos-#{p1.id}") |> render_click()
      assert has_element?(view, "#selection-bar", "1 selected")
      refute has_element?(view, "#lightbox")
    end

    test "selecting and deselecting a photo toggles the count",
         %{conn: conn, gallery: gallery, family: family, org: org, photos: [p1, p2 | _]} do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#select-btn") |> render_click()

      # Select two photos
      view |> element("#photos-#{p1.id}") |> render_click()
      view |> element("#photos-#{p2.id}") |> render_click()
      assert has_element?(view, "#selection-bar", "2 selected")

      # Deselect one
      view |> element("#photos-#{p1.id}") |> render_click()
      assert has_element?(view, "#selection-bar", "1 selected")
    end

    test "deleting selected photos removes only those photos",
         %{conn: conn, gallery: gallery, family: family, org: org, photos: [p1, p2, p3]} do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      # Enter select mode, select p1 and p3 only
      view |> element("#select-btn") |> render_click()
      view |> element("#photos-#{p1.id}") |> render_click()
      view |> element("#photos-#{p3.id}") |> render_click()
      assert has_element?(view, "#selection-bar", "2 selected")

      # Request deletion — confirmation modal should appear
      view |> element("button", "Delete") |> render_click()
      assert has_element?(view, "p", "This cannot be undone")

      # Confirm deletion
      view |> element("#confirm-delete-photos-modal button", "Delete") |> render_click()

      # Selected photos are gone, unselected photo remains
      refute has_element?(view, "#photos-#{p1.id}")
      refute has_element?(view, "#photos-#{p3.id}")
      assert has_element?(view, "#photos-#{p2.id}")

      # Selection mode is exited
      refute has_element?(view, "#selection-bar")
    end

    test "cancelling delete keeps all photos",
         %{conn: conn, gallery: gallery, family: family, org: org, photos: [p1, p2, p3]} do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#select-btn") |> render_click()
      view |> element("#photos-#{p1.id}") |> render_click()

      # Request then cancel deletion
      view |> element("button", "Delete") |> render_click()
      view |> element("#confirm-delete-photos-modal button", "Cancel") |> render_click()

      # All photos still present
      assert has_element?(view, "#photos-#{p1.id}")
      assert has_element?(view, "#photos-#{p2.id}")
      assert has_element?(view, "#photos-#{p3.id}")
    end
  end

  describe "upload modal" do
    test "uploading a file opens the modal and shows progress", %{
      conn: conn,
      gallery: gallery,
      family: family,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

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
      family: family,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

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
