defmodule Web.UserFlows.KinshipInLawTest do
  use Web.E2ECase

  # In-law kinship detection — English and Spanish
  #
  # Given a family tree with a parent (male), two children (son/daughter),
  # the son's wife, and an unrelated person
  # When two people are selected on the kinship page
  # Then in-law relationships are detected and labeled correctly
  #
  # Scenarios covered:
  # 1. Direct spouse — son + wife → "Husband" (en-US, male)
  # 2. Parent-in-law — parent (male) + wife → "Father-in-law" (en-US)
  # 3. Child-in-law Spanish — wife (female) + parent → "Nuera" (es-UY)
  # 4. Sibling-in-law — daughter + wife → "Sister-in-law" (en-US, female)
  # 5. No relationship — unrelated + wife → "No relationship found"
  # 6. URL sharing — ?person_a=&person_b= loads result immediately
  # 7. Blood takes precedence — son + daughter → "Sibling" (blood, not in-law)
  # 8. Swap reverses direction — parent→wife swaps to wife→parent label changes
  # 9. Divorced partner still shows in-law — divorce doesn't remove in-law detection
  # 10. Extended in-law (uncle-in-law) — grandparent of son + wife → extended in-law

  setup do
    family = insert(:family, name: "In-law Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    # parent — male, root of the blood tree
    parent =
      insert(:person,
        given_name: "Robert",
        surname: "InLaw",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(parent, family)

    # son — male child of parent
    son =
      insert(:person,
        given_name: "James",
        surname: "InLaw",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(son, family)
    Ancestry.Relationships.create_relationship(parent, son, "parent", %{role: "father"})

    # daughter — female child of parent
    daughter =
      insert(:person,
        given_name: "Sofia",
        surname: "InLaw",
        gender: "female",
        organization: family.organization
      )

    Ancestry.People.add_to_family(daughter, family)
    Ancestry.Relationships.create_relationship(parent, daughter, "parent", %{role: "father"})

    # wife — married to son (in-law connection)
    wife =
      insert(:person,
        given_name: "Laura",
        surname: "Bride",
        gender: "female",
        organization: family.organization
      )

    Ancestry.People.add_to_family(wife, family)
    Ancestry.Relationships.create_relationship(son, wife, "married", %{})

    # unrelated — no connection to anyone
    unrelated =
      insert(:person,
        given_name: "Stranger",
        surname: "Nobody",
        organization: family.organization
      )

    Ancestry.People.add_to_family(unrelated, family)

    %{
      family: family,
      org: org,
      parent: parent,
      son: son,
      daughter: daughter,
      wife: wife,
      unrelated: unrelated
    }
  end

  # Test 1: Direct spouse — son as A, wife as B → "Husband" (male, en-US)
  test "direct spouse shows 'Husband' label and 'Related by marriage' note", %{
    conn: conn,
    family: family,
    org: org,
    son: son,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects son as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{son.id}"))

    # And selects wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then the in-law result section is shown
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Husband")
    |> assert_has(test_id("kinship-in-law-note"), text: "Related by marriage")
  end

  # Test 2: Parent-in-law — parent (male) as A, wife as B → "Father-in-law" (en-US)
  test "parent-in-law shows 'Father-in-law' label", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects parent as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{parent.id}"))

    # And selects wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then "Father-in-law" is shown (parent is male, and is parent-in-law of wife)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Father-in-law")
    |> assert_has(test_id("kinship-in-law-note"), text: "Related by marriage")
  end

  # Test 3: Child-in-law in Spanish — wife (female) as A, parent as B → "Nuera" (es-UY)
  test "Spanish locale — wife as A shows 'Nuera' (not Yerno, because A is female)", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent,
    wife: wife
  } do
    # Given a logged-in user with Spanish locale
    spanish_account = insert(:account, role: :admin, locale: "es-UY")

    conn =
      conn
      |> PhoenixTest.visit("/test/session/#{spanish_account.id}")

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects wife (female) as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{wife.id}"))

    # And selects parent as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{parent.id}"))

    # Then the label is "Nuera" (female child-in-law) — NOT "Yerno" (which is male)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Nuera")
  end

  # Test 4: Sibling-in-law — daughter (female) as A, wife as B → "Sister-in-law" (en-US)
  test "sibling-in-law shows 'Sister-in-law' label", %{
    conn: conn,
    family: family,
    org: org,
    daughter: daughter,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects daughter (female) as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{daughter.id}"))

    # And selects wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then "Sister-in-law" is shown (daughter is female, sibling-in-law of wife)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Sister-in-law")
    |> assert_has(test_id("kinship-in-law-note"), text: "Related by marriage")
  end

  # Test 5: No relationship — unrelated as A, wife as B → "No relationship found"
  test "unrelated person and wife shows 'No relationship found'", %{
    conn: conn,
    family: family,
    org: org,
    unrelated: unrelated,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects unrelated as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{unrelated.id}"))

    # And selects wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then "No relationship found" is shown
    conn
    |> assert_has(test_id("kinship-no-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-no-result"), text: "No relationship found")
  end

  # Test 6: URL sharing — navigate with ?person_a=&person_b= → result loads immediately
  test "URL with person_a and person_b query params loads in-law result immediately", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user navigates directly to the kinship page with query params
    conn =
      conn
      |> visit(
        ~p"/org/#{org.id}/families/#{family.id}/kinship?person_a=#{parent.id}&person_b=#{wife.id}"
      )
      |> wait_liveview()

    # Then the result is shown immediately without any user interaction
    conn
    |> assert_has(test_id("kinship-person-a-selected"), text: "Robert InLaw")
    |> assert_has(test_id("kinship-person-b-selected"), text: "Laura Bride")
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Father-in-law")
  end

  # Test 7: Blood takes precedence — son as A, daughter as B → "Sibling" (blood, not in-law)
  test "blood relationship takes precedence over in-law for son and daughter", %{
    conn: conn,
    family: family,
    org: org,
    son: son,
    daughter: daughter
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects son as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{son.id}"))

    # And selects daughter as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{daughter.id}"))

    # Then "Sibling" is shown (blood relationship), NOT an in-law label
    conn
    |> assert_has(test_id("kinship-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Sibling")
    |> refute_has(test_id("kinship-in-law-result"))
    |> refute_has(test_id("kinship-in-law-note"))
  end

  # Test 8: Swap reverses direction — parent→wife swaps → wife→parent, label changes
  test "swapping parent and wife reverses the in-law direction", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent,
    wife: wife
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects parent (male) as Person A, wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{parent.id}"))

    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then "Father-in-law" is shown (parent is male)
    conn =
      conn
      |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
      |> assert_has(test_id("kinship-relationship-label"), text: "Father-in-law")

    # When the user clicks the swap button
    conn = click(conn, test_id("kinship-swap-btn"))

    # Then Person A is now wife (female) and Person B is parent
    conn =
      conn
      |> assert_has(test_id("kinship-person-a-selected"), text: "Laura Bride")
      |> assert_has(test_id("kinship-person-b-selected"), text: "Robert InLaw")

    # And the label changes to "Daughter-in-law" (wife is female, A is child-in-law)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Daughter-in-law")
  end

  # Test 9: Divorced partner still shows in-law
  test "divorced partner still enables in-law detection for relatives", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent
  } do
    # Given an ex-wife who was divorced from son
    ex_wife =
      insert(:person,
        given_name: "Clara",
        surname: "ExBride",
        gender: "female",
        organization: family.organization
      )

    Ancestry.People.add_to_family(ex_wife, family)

    son =
      insert(:person,
        given_name: "Marco",
        surname: "InLaw",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(son, family)
    Ancestry.Relationships.create_relationship(parent, son, "parent", %{role: "father"})
    # Divorced relationship between son and ex_wife
    Ancestry.Relationships.create_relationship(son, ex_wife, "divorced", %{})

    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects parent (male) as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{parent.id}"))

    # And selects ex_wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{ex_wife.id}"))

    # Then the in-law relationship is still detected (divorce doesn't remove the link)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Father-in-law")
    |> assert_has(test_id("kinship-in-law-note"), text: "Related by marriage")
  end

  # Test 10: Extended in-law (grandparent-in-law / uncle-in-law)
  test "grandparent of son shows 'Grandparent-in-law' for wife", %{
    conn: conn,
    family: family,
    org: org,
    parent: parent,
    wife: wife
  } do
    # Given a grandparent (parent's parent) added to the family
    grandparent =
      insert(:person,
        given_name: "Harold",
        surname: "Senior",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(grandparent, family)
    Ancestry.Relationships.create_relationship(grandparent, parent, "parent", %{role: "father"})

    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects grandparent as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{grandparent.id}"))

    # And selects wife as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{wife.id}"))

    # Then "Grandparent-in-law" is shown (grandparent is 2 steps above wife's partner)
    conn
    |> assert_has(test_id("kinship-in-law-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Grandparent-in-law")
    |> assert_has(test_id("kinship-in-law-note"), text: "Related by marriage")
  end
end
