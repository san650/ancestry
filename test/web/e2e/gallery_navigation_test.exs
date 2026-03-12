defmodule Web.E2E.GalleryNavigationTest do
  use Web.E2ECase

  alias Family.Galleries
  alias Family.Galleries.Photo
  alias Family.Repo

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery"})

    # Insert a processed photo directly — bypasses Oban job since no real
    # image processing is needed; status: "processed" makes it render as a
    # clickable img card rather than a pending placeholder.
    {:ok, photo} =
      %Photo{}
      |> Photo.changeset(%{
        gallery_id: gallery.id,
        original_path: "test/fixtures/test_image.jpg",
        original_filename: "test.jpg",
        content_type: "image/jpeg",
        status: "processed"
      })
      |> Repo.insert()

    %{gallery: gallery, photo: photo}
  end

  test "navigate from gallery list to a gallery and open a photo", %{conn: conn, gallery: gallery} do
    conn
    |> visit(~p"/galleries")
    |> wait_liveview()
    |> click_link(gallery.name)
    |> wait_liveview()
    |> click("#photo-grid [id^='photos-'][data-phx-stream]")
    |> assert_has("#lightbox")
  end
end
