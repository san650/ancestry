defmodule Web.UserFlows.GalleryBackButtonAfterLightboxTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, family: family, name: "Photos")

    photo =
      insert(:photo, gallery: gallery, original_filename: "beach.jpg")
      |> ensure_photo_file()

    %{org: org, family: family, gallery: gallery, photo: photo}
  end

  # Given a gallery with at least one processed photo
  # When the user opens the gallery and taps a photo to maximize it
  # Then the lightbox opens
  #
  # When the user closes the lightbox
  # Then the breadcrumb navigation still works
  # And clicking the family breadcrumb navigates back to the family page
  test "breadcrumb navigation works after closing lightbox", %{
    conn: conn,
    org: org,
    family: family,
    gallery: gallery,
    photo: photo
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # Open the lightbox
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # Close lightbox
    conn =
      conn
      |> click("#lightbox button[aria-label='Close']")
      |> refute_has("#lightbox")

    # Breadcrumb navigates back to the family page
    conn
    |> click_link("nav[aria-label='Breadcrumb']:visible a", "Test Family")
    |> wait_liveview()
    |> assert_has(test_id("family-name"), text: "Test Family")
  end
end
