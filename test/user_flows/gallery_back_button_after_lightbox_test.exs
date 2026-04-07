defmodule Web.UserFlows.GalleryBackButtonAfterLightboxTest do
  use Web.E2ECase

  # The FAB is `lg:hidden`, so it only renders below 1024px wide. Force a
  # mobile-sized browser context for this test.
  @moduletag browser_context_opts: [viewport: %{width: 414, height: 896}]

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
  # When the user opens the gallery
  # Then the floating back button is visible
  #
  # When the user taps a photo to maximize it
  # Then the floating back button is hidden while the lightbox is open
  #
  # When the user closes the lightbox
  # Then the floating back button is visible again
  # And tapping it navigates back to the family page
  test "back FAB is hidden during lightbox and works after close", %{
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
      |> assert_has("#gallery-back-fab")

    # Open the lightbox
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # FAB should not be in the DOM while lightbox is open
    conn = refute_has(conn, "#gallery-back-fab")

    # Close lightbox
    conn =
      conn
      |> click("#lightbox button[aria-label='Close']")
      |> refute_has("#lightbox")

    # FAB is back and navigates back to the family page
    conn
    |> assert_has("#gallery-back-fab")
    |> click("#gallery-back-fab")
    |> wait_liveview()
    |> assert_has(test_id("family-name"), text: "Test Family")
  end
end
