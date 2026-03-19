defmodule Web.UserFlows.PersonPhotosTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.People

  # Given a person tagged in processed photos across galleries
  # When the user visits the person show page
  # Then the photos section shows with the tagged photos in a masonry grid
  #
  # When the user clicks a photo
  # Then the lightbox opens showing that photo
  #
  # When the user presses Escape
  # Then the lightbox closes and the person show page is visible again

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Summer 2024", family_id: family.id})
    {:ok, person} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})

    {:ok, photo1} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test1.jpg",
        original_filename: "beach.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo1} = Galleries.update_photo_processed(photo1, "beach.jpg")

    {:ok, photo2} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test2.jpg",
        original_filename: "sunset.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo2} = Galleries.update_photo_processed(photo2, "sunset.jpg")

    {:ok, _} = Galleries.tag_person_in_photo(photo1.id, person.id, 0.5, 0.5)
    {:ok, _} = Galleries.tag_person_in_photo(photo2.id, person.id, 0.3, 0.7)

    %{family: family, person: person, photo1: photo1, photo2: photo2}
  end

  test "person show page displays tagged photos and lightbox works", %{
    conn: conn,
    person: person,
    photo1: photo1,
    photo2: photo2
  } do
    {:ok, view, html} = live(conn, ~p"/people/#{person.id}")

    # Photos section is visible with count badge showing "2"
    assert html =~ "Photos"
    assert has_element?(view, "#person-photos-section")
    assert has_element?(view, "#person-photo-grid")
    assert html =~ "2"

    # Both photos should appear in the grid (stream DOM ids)
    assert has_element?(view, "#person_photos-#{photo1.id}")
    assert has_element?(view, "#person_photos-#{photo2.id}")

    # Click a photo to open lightbox by sending the event directly
    # (the grid uses JS.push so we send the event manually)
    render_click(view, "photo_clicked", %{"id" => photo1.id})

    # Lightbox should be visible and show the clicked photo's filename
    assert has_element?(view, "#lightbox")
    lightbox_html = render(view)
    assert lightbox_html =~ "beach.jpg"

    # Navigate to next photo with ArrowRight
    render_keydown(view, "lightbox_keydown", %{"key" => "ArrowRight"})
    lightbox_html = render(view)
    assert lightbox_html =~ "sunset.jpg"

    # Navigate back with ArrowLeft
    render_keydown(view, "lightbox_keydown", %{"key" => "ArrowLeft"})
    lightbox_html = render(view)
    assert lightbox_html =~ "beach.jpg"

    # Close lightbox with Escape
    render_keydown(view, "lightbox_keydown", %{"key" => "Escape"})
    refute has_element?(view, "#lightbox")

    # Person show page is still visible
    assert has_element?(view, "#person-photos-section")

    # Re-open lightbox and close via close_lightbox event
    render_click(view, "photo_clicked", %{"id" => photo2.id})
    assert has_element?(view, "#lightbox")

    render_click(view, "close_lightbox")
    refute has_element?(view, "#lightbox")
    assert has_element?(view, "#person-photos-section")
  end

  test "person with no tagged photos does not show photos section", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "Another Family"})
    {:ok, person} = People.create_person(family, %{given_name: "Bob", surname: "Jones"})

    {:ok, _view, html} = live(conn, ~p"/people/#{person.id}")

    refute html =~ "person-photos-section"
  end
end
