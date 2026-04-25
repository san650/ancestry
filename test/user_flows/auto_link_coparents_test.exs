defmodule Web.UserFlows.AutoLinkCoparentsTest do
  use Web.E2ECase

  # Auto-create partner relationship when adding second parent
  #
  # Given a family with a child who has one parent (father)
  # When the user navigates to the child's person page
  # And clicks "Add Parent"
  # And creates a new person as mother
  # Then the mother is added as a parent
  # And a partner relationship is auto-created between the father and mother
  #
  # Given a family with a child who has no parents
  # When the user creates a new person as father (no gender set)
  # Then the person's gender is auto-set to male
  #
  # Given two parents already married
  # When the second parent is added to the child via link existing
  # Then no duplicate partner relationship is created

  setup do
    family = insert(:family, name: "Nuclear Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    child =
      insert(:person,
        given_name: "Charlie",
        surname: "Nuclear",
        organization: family.organization
      )

    Ancestry.People.add_to_family(child, family)

    %{family: family, org: org, child: child}
  end

  test "adding second parent auto-creates partner relationship", %{
    conn: conn,
    family: family,
    org: org,
    child: child
  } do
    father =
      insert(:person,
        given_name: "Frank",
        surname: "Nuclear",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(father, family)
    Ancestry.Relationships.create_relationship(father, child, "parent", %{role: "father"})

    conn = log_in_e2e(conn, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people/#{child.id}?from_family=#{family.id}")
      |> wait_liveview()
      |> assert_has("#parents-section", text: "Frank")

    # Open Add Parent modal → Create new person
    conn =
      conn
      |> click("#add-parent-btn")
      |> click("#add-rel-create-new-btn")
      |> fill_in("Given name", with: "Martha")
      |> fill_in("Surname", with: "Nuclear")
      |> click_button("Create")

    # Now in metadata step — select mother role and submit
    conn =
      conn
      |> click("#add-parent-form button[type='submit']")

    # Verify both parents are now shown
    conn
    |> assert_has("#parents-section", text: "Frank")
    |> assert_has("#parents-section", text: "Martha")

    # Verify the auto-created partner relationship exists in DB
    partners = Ancestry.Relationships.get_active_partners(father.id)
    assert length(partners) == 1
    assert {partner, rel} = hd(partners)
    assert partner.given_name == "Martha"
    assert rel.type == "relationship"
  end

  test "adding parent auto-sets gender based on role", %{
    conn: conn,
    family: family,
    org: org,
    child: child
  } do
    conn = log_in_e2e(conn, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people/#{child.id}?from_family=#{family.id}")
      |> wait_liveview()

    # Create a new person (no gender) via Add Parent → Create new
    conn =
      conn
      |> click("#add-parent-btn")
      |> click("#add-rel-create-new-btn")
      |> fill_in("Given name", with: "Pat")
      |> fill_in("Surname", with: "Nuclear")
      |> click_button("Create")

    # Role defaults to "mother" for a person with no gender.
    # Submit with the default — gender should be auto-set to female.
    conn =
      conn
      |> click("#add-parent-form button[type='submit']")

    conn
    |> assert_has("#parents-section", text: "Pat")

    # Find the newly-created person and verify gender was auto-set
    [pat] =
      Ancestry.People.search_family_members("Pat", family.id, child.id)

    assert pat.gender == "female"
  end

  test "does not create duplicate partner when parents already married", %{
    conn: conn,
    family: family,
    org: org,
    child: child
  } do
    father =
      insert(:person,
        given_name: "Henry",
        surname: "Married",
        gender: "male",
        organization: family.organization
      )

    mother =
      insert(:person,
        given_name: "Helen",
        surname: "Married",
        gender: "female",
        organization: family.organization
      )

    Ancestry.People.add_to_family(father, family)
    Ancestry.People.add_to_family(mother, family)
    Ancestry.Relationships.create_relationship(father, mother, "married", %{marriage_year: 2000})
    Ancestry.Relationships.create_relationship(father, child, "parent", %{role: "father"})

    conn = log_in_e2e(conn, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people/#{child.id}?from_family=#{family.id}")
      |> wait_liveview()
      |> assert_has("#parents-section", text: "Henry")

    # Link existing person as second parent
    conn =
      conn
      |> click("#add-parent-btn")
      |> click("#add-rel-link-existing-btn")
      |> PhoenixTest.Playwright.type("#relationship-search-input", "Helen")
      |> click("#search-result-#{mother.id}")
      |> click("#add-parent-form button[type='submit']")

    conn
    |> assert_has("#parents-section", text: "Henry")
    |> assert_has("#parents-section", text: "Helen")

    # Should still have exactly 1 partner relationship — the original married one
    all_partners = Ancestry.Relationships.get_all_partners(father.id)
    assert length(all_partners) == 1
    assert {_, rel} = hd(all_partners)
    assert rel.type == "married"
  end
end
