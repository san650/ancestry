defmodule Web.UserFlows.PhotoToPersonNavigationTest do
  use Web.E2ECase

  # Navigate from photo lightbox to person show page
  #
  # Given a gallery with a processed photo and two tagged people
  # When the user opens the lightbox and the info panel
  # Then each person row has a link to the person show page
  #
  # When the user clicks a person name
  # Then the app navigates to that person's show page

  setup do
    family = insert(:family, name: "Navigation Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg")
      |> ensure_photo_file()

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Nav",
        organization: family.organization
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Nav",
        organization: family.organization
      )

    {:ok, _} = Ancestry.Galleries.tag_person_in_photo(photo.id, alice.id, 0.3, 0.4)
    {:ok, _} = Ancestry.Galleries.tag_person_in_photo(photo.id, bob.id, 0.6, 0.7)

    %{family: family, gallery: gallery, photo: photo, alice: alice, bob: bob, org: org}
  end

  test "clicking a tagged person navigates to person show page", %{
    conn: conn,
    family: family,
    gallery: gallery,
    photo: photo,
    alice: alice,
    bob: bob,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Navigate to the gallery show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # Click the photo to open lightbox
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # Open the side panel
    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-person-list")

    # Both tagged people should be visible
    conn =
      conn
      |> assert_has("#photo-person-list", text: "Alice Nav")
      |> assert_has("#photo-person-list", text: "Bob Nav")

    # Verify each person has a link with the correct href
    conn =
      conn
      |> assert_has(
        "#photo-person-list a[href='/org/#{org.id}/people/#{alice.id}']",
        text: "Alice Nav"
      )
      |> assert_has(
        "#photo-person-list a[href='/org/#{org.id}/people/#{bob.id}']",
        text: "Bob Nav"
      )

    # Click Alice's name to navigate to her person show page
    conn =
      conn
      |> click("#photo-person-list a[href='/org/#{org.id}/people/#{alice.id}']")

    # Should be on Alice's person show page
    conn
    |> assert_has("nav[aria-label='Breadcrumb']:visible", text: "Alice Nav")
  end
end
