defmodule Web.E2E.GalleryNavigationTest do
  use Web.E2ECase

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})

    # Insert a processed photo directly — bypasses Oban job since no real
    # image processing is needed; status: "processed" makes it render as a
    # clickable img card rather than a pending placeholder.
    {:ok, _photo} =
      %Photo{}
      |> Photo.changeset(%{
        gallery_id: gallery.id,
        original_path: "test/fixtures/test_image.jpg",
        original_filename: "test.jpg",
        content_type: "image/jpeg",
        status: "processed"
      })
      |> Repo.insert()

    %{gallery: gallery, family: family}
  end

  test "navigate from gallery list to a gallery and open a photo", %{
    conn: conn,
    gallery: gallery,
    family: family
  } do
    conn
    |> visit(~p"/families/#{family.id}")
    |> wait_liveview()
    |> click_link(gallery.name)
    |> wait_liveview()
    |> click("#photo-grid [id^='photos-'][data-phx-stream]")
    |> assert_has("#lightbox")
  end
end
