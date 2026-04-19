defmodule Web.UserFlows.CalculatingKinshipTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Kinship Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    # Grandparent
    grandpa =
      insert(:person, given_name: "George", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(grandpa, family)

    grandma =
      insert(:person, given_name: "Martha", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(grandma, family)

    # Two parents who are siblings (children of grandpa and grandma)
    parent_a =
      insert(:person, given_name: "Alice", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(parent_a, family)

    parent_b =
      insert(:person, given_name: "Bob", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(parent_b, family)

    # Make parents children of grandparents
    Ancestry.Relationships.create_relationship(grandpa, parent_a, "parent", %{role: "father"})
    Ancestry.Relationships.create_relationship(grandma, parent_a, "parent", %{role: "mother"})
    Ancestry.Relationships.create_relationship(grandpa, parent_b, "parent", %{role: "father"})
    Ancestry.Relationships.create_relationship(grandma, parent_b, "parent", %{role: "mother"})

    # Two cousins (children of the two parents)
    cousin_a =
      insert(:person,
        given_name: "Charlie",
        surname: "Kinship",
        organization: family.organization
      )

    Ancestry.People.add_to_family(cousin_a, family)

    cousin_b =
      insert(:person, given_name: "Diana", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(cousin_b, family)

    Ancestry.Relationships.create_relationship(parent_a, cousin_a, "parent", %{role: "father"})
    Ancestry.Relationships.create_relationship(parent_b, cousin_b, "parent", %{role: "father"})

    # Child of cousin_b (for testing "removed" relationships)
    child_of_cousin =
      insert(:person, given_name: "Frank", surname: "Kinship", organization: family.organization)

    Ancestry.People.add_to_family(child_of_cousin, family)

    Ancestry.Relationships.create_relationship(cousin_b, child_of_cousin, "parent", %{
      role: "father"
    })

    # One unrelated person
    unrelated =
      insert(:person, given_name: "Eve", surname: "Stranger", organization: family.organization)

    Ancestry.People.add_to_family(unrelated, family)

    %{
      family: family,
      grandpa: grandpa,
      grandma: grandma,
      parent_a: parent_a,
      parent_b: parent_b,
      cousin_a: cousin_a,
      cousin_b: cousin_b,
      child_of_cousin: child_of_cousin,
      unrelated: unrelated,
      org: org
    }
  end

  test "full kinship flow: select cousins, swap, clear, and unrelated people", %{
    conn: conn,
    family: family,
    cousin_a: cousin_a,
    cousin_b: cousin_b,
    unrelated: unrelated,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Navigate to the family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click(test_id("family-card-#{family.id}"))
      |> wait_liveview()

    # Click the Kinship button to navigate to the kinship page
    conn =
      conn
      |> click(test_id("family-kinship-btn"))
      |> wait_liveview()

    # Verify empty state is shown
    conn = assert_has(conn, test_id("kinship-empty-state"))

    # --- Select two cousins ---

    # Open Person A dropdown and select Charlie
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> assert_has(test_id("kinship-person-a-search"))

    conn = click(conn, test_id("kinship-person-a-option-#{cousin_a.id}"))

    # Verify Person A is selected
    conn = assert_has(conn, test_id("kinship-person-a-selected"), text: "Charlie Kinship")

    # Open Person B dropdown and select Diana
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> assert_has(test_id("kinship-person-b-search"))

    conn = click(conn, test_id("kinship-person-b-option-#{cousin_b.id}"))

    # Verify Person B is selected
    conn = assert_has(conn, test_id("kinship-person-b-selected"), text: "Diana Kinship")

    # Verify the "First Cousin" relationship is displayed
    conn = assert_has(conn, test_id("kinship-result"), timeout: 5_000)
    conn = assert_has(conn, test_id("kinship-relationship-label"), text: "First Cousin")

    # Verify DNA percentage is shown for 1st cousins (12.5%)
    conn = assert_has(conn, test_id("kinship-dna-percentage"), text: "12.5% shared DNA")

    # First cousins are NOT "removed", so no footnote
    conn = refute_has(conn, test_id("kinship-removed-footnote"))

    # Verify directional label shows correct direction
    conn =
      assert_has(conn, test_id("kinship-directional-label"),
        text: "Charlie Kinship is Diana Kinship's first cousin"
      )

    # Verify path visualization is displayed
    conn = assert_has(conn, test_id("kinship-path"))

    # --- Swap the people ---

    conn = click(conn, test_id("kinship-swap-btn"))

    # After swap, Person A should be Diana and Person B should be Charlie
    conn = assert_has(conn, test_id("kinship-person-a-selected"), text: "Diana Kinship")
    conn = assert_has(conn, test_id("kinship-person-b-selected"), text: "Charlie Kinship")

    # Relationship should still be First Cousin
    conn = assert_has(conn, test_id("kinship-relationship-label"), text: "First Cousin")

    # Directional label should update to reflect the swap
    conn =
      assert_has(conn, test_id("kinship-directional-label"),
        text: "Diana Kinship is Charlie Kinship's first cousin"
      )

    # --- Clear a selection ---

    conn = click(conn, test_id("kinship-person-a-clear"))

    # Result should disappear, empty state should show
    conn = refute_has(conn, test_id("kinship-result"))
    conn = assert_has(conn, test_id("kinship-empty-state"))

    # --- Select two unrelated people ---

    # Select Eve (unrelated) as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> assert_has(test_id("kinship-person-a-search"))

    conn = click(conn, test_id("kinship-person-a-option-#{unrelated.id}"))

    # Person B should still be Charlie from before
    conn = assert_has(conn, test_id("kinship-person-a-selected"), text: "Eve Stranger")
    conn = assert_has(conn, test_id("kinship-person-b-selected"), text: "Charlie Kinship")

    # "No relationship found" should be shown (unrelated people have no in-law path either)
    conn
    |> assert_has(test_id("kinship-no-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-no-result"), text: "No relationship found")
  end

  test "removed relationship shows footnote and DNA percentage", %{
    conn: conn,
    family: family,
    cousin_a: cousin_a,
    child_of_cousin: child_of_cousin,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Navigate directly to the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # Select cousin_a as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))

    conn = click(conn, test_id("kinship-person-a-option-#{cousin_a.id}"))

    # Select child_of_cousin as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))

    conn = click(conn, test_id("kinship-person-b-option-#{child_of_cousin.id}"))

    # Verify "First Cousin, Once Removed" relationship
    conn = assert_has(conn, test_id("kinship-result"), timeout: 5_000)

    conn =
      assert_has(conn, test_id("kinship-relationship-label"), text: "First Cousin, Once Removed")

    # Verify DNA percentage for 1st cousin once removed (6.25%)
    conn = assert_has(conn, test_id("kinship-dna-percentage"), text: "6.25% shared DNA")

    # Verify the "removed" footnote appears
    conn
    |> assert_has(test_id("kinship-removed-footnote"))
  end
end
