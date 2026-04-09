defmodule Web.UserFlows.FamilyIndexBatchDeleteTest do
  use Web.E2ECase

  # Given multiple families in an organization
  # When the user enters selection mode from the family index toolbar
  # And taps two family cards
  # Then the cards are highlighted as selected
  # And the selection bar shows "2 selected"
  #
  # When the user taps Delete in the selection bar
  # Then a batch confirmation modal is shown
  #
  # When the user confirms
  # Then both families are removed from the index
  # And the third family persists
  # And selection mode exits
  setup do
    family1 = insert(:family, name: "Alpha")
    org = Ancestry.Organizations.get_organization!(family1.organization_id)
    family2 = insert(:family, organization: org, name: "Beta")
    family3 = insert(:family, organization: org, name: "Gamma")
    %{org: org, family1: family1, family2: family2, family3: family3}
  end

  test "batch delete two families via selection mode", %{
    conn: conn,
    org: org,
    family1: family1,
    family2: family2,
    family3: family3
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click(test_id("family-index-select-btn"))
      |> wait_liveview()

    # Tap two cards
    conn =
      conn
      |> click(test_id("family-card-#{family1.id}"))
      |> click(test_id("family-card-#{family2.id}"))
      |> wait_liveview()
      |> assert_has(test_id("selection-bar"), text: "2 selected")

    # Open the confirmation modal
    conn =
      conn
      |> click(test_id("selection-bar-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("confirm-delete-families-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("confirm-delete-families-confirm-btn"))
      |> wait_liveview()

    # The two selected families should be gone, the third still present
    conn
    |> refute_has(test_id("family-card-#{family1.id}"))
    |> refute_has(test_id("family-card-#{family2.id}"))
    |> assert_has(test_id("family-card-#{family3.id}"))

    refute Ancestry.Repo.get(Ancestry.Families.Family, family1.id)
    refute Ancestry.Repo.get(Ancestry.Families.Family, family2.id)
    assert Ancestry.Repo.get(Ancestry.Families.Family, family3.id)
  end
end
