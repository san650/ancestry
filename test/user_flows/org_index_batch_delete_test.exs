defmodule Web.UserFlows.OrgIndexBatchDeleteTest do
  use Web.E2ECase

  # Given multiple organizations
  # When the user enters selection mode from the org index toolbar
  # And taps two organization cards
  # Then both are highlighted and the selection bar shows "2 selected"
  #
  # When the user taps Delete and confirms
  # Then both orgs are removed from the index
  # And the third org persists
  # And selection mode exits
  setup do
    org1 = insert(:organization, name: "First Org")
    org2 = insert(:organization, name: "Second Org")
    org3 = insert(:organization, name: "Third Org")
    %{org1: org1, org2: org2, org3: org3}
  end

  test "batch delete two organizations via selection mode", %{
    conn: conn,
    org1: org1,
    org2: org2,
    org3: org3
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()

    # Tap two cards
    conn =
      conn
      |> click(test_id("org-card-#{org1.id}"))
      |> click(test_id("org-card-#{org2.id}"))
      |> wait_liveview()
      |> assert_has(test_id("selection-bar"), text: "2 selected")

    # Open the confirmation modal
    conn =
      conn
      |> click(test_id("selection-bar-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("confirm-delete-orgs-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("confirm-delete-orgs-confirm-btn"))
      |> wait_liveview()

    # The two selected orgs should be gone, the third still present
    conn
    |> refute_has(test_id("org-card-#{org1.id}"))
    |> refute_has(test_id("org-card-#{org2.id}"))
    |> assert_has(test_id("org-card-#{org3.id}"))

    refute Ancestry.Repo.get(Ancestry.Organizations.Organization, org1.id)
    refute Ancestry.Repo.get(Ancestry.Organizations.Organization, org2.id)
    assert Ancestry.Repo.get(Ancestry.Organizations.Organization, org3.id)
  end
end
