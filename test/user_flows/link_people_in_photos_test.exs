defmodule Web.UserFlows.LinkPeopleInPhotosTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Photo Tag Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Summer 2025", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "beach.jpg")
      |> ensure_photo_file()

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Wonderland",
        organization: family.organization
      )

    bob =
      insert(:person, given_name: "Bob", surname: "Builder", organization: family.organization)

    %{family: family, gallery: gallery, photo: photo, alice: alice, bob: bob, org: org}
  end

  test "tag and untag people in a photo", %{
    conn: conn,
    family: family,
    gallery: gallery,
    photo: photo,
    alice: alice,
    org: org
  } do
    # Navigate to the gallery show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # Click the photo to open lightbox (use the stream DOM id for the photo)
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")

    # Open the side panel
    conn =
      conn
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-person-list")

    # The people list should show the empty state
    conn =
      conn
      |> assert_has("#photo-person-list", text: "Click on the photo to tag people")

    # Click on the lightbox image to open the tag popover.
    # We use evaluate to dispatch a click at the center of the image.
    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        (function() {
          const img = document.querySelector('#lightbox-image');
          const rect = img.getBoundingClientRect();
          const x = rect.left + rect.width / 2;
          const y = rect.top + rect.height / 2;
          img.dispatchEvent(new MouseEvent('click', {
            clientX: x,
            clientY: y,
            bubbles: true
          }));
        })();
      """)

    # The popover with search input should appear
    conn =
      conn
      |> assert_has("#tag-search-input", timeout: 3_000)

    # Type the person name to search
    conn = PhoenixTest.Playwright.type(conn, "#tag-search-input", "Alice")

    # Wait for debounced search results — person should appear as a button
    conn =
      conn
      |> assert_has("[data-person-id='#{alice.id}']", timeout: 5_000)

    # Click the search result to tag the person
    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        document.querySelector("[data-person-id='#{alice.id}']").click();
      """)

    # The person should now appear in the panel people list
    conn =
      conn
      |> assert_has("#photo-person-list", text: "Alice Wonderland", timeout: 5_000)

    # A circle should be rendered on the photo for this person
    conn =
      conn
      |> assert_has("[data-circle-person-id='#{alice.id}']", timeout: 3_000)

    # Now untag the person by clicking the X button in the panel.
    # The untag button is inside the person row — find it and click it.
    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        (function() {
          const row = document.querySelector("#photo-person-list [data-person-id='#{alice.id}']");
          const btn = row.querySelector("button[phx-click='untag_person']");
          btn.click();
        })();
      """)

    # The person should be removed from the panel
    conn =
      conn
      |> refute_has("#photo-person-list [data-person-id='#{alice.id}']", timeout: 5_000)

    # The empty state should be shown again
    conn
    |> assert_has("#photo-person-list", text: "Click on the photo to tag people")
  end
end
