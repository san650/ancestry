defmodule Web.UserFlows.KinshipGenderedLabelsTest do
  use Web.E2ECase

  # Gendered kinship labels — English and Spanish
  #
  # Given a family tree with grandparents, a male and female child, and a grandson
  # When two people are selected on the kinship page
  # Then the relationship label is gendered based on person A's gender field
  #
  # Scenarios covered:
  # 1. Male grandparent → grandson  → "Grandparent" (English, gender-neutral msgid)
  # 2. Female grandparent → grandson → "Grandparent" (English, gender-neutral msgid)
  # 3. Male grandparent → grandson  → "Abuelo" (Spanish, male)
  # 4. Female grandparent → grandson → "Abuela" (Spanish, female)

  setup do
    family = insert(:family, name: "Gendered Kinship Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    grandfather =
      insert(:person,
        given_name: "Carlos",
        surname: "Gendered",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(grandfather, family)

    grandmother =
      insert(:person,
        given_name: "Maria",
        surname: "Gendered",
        gender: "female",
        organization: family.organization
      )

    Ancestry.People.add_to_family(grandmother, family)

    father =
      insert(:person,
        given_name: "Luis",
        surname: "Gendered",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(father, family)

    Ancestry.Relationships.create_relationship(grandfather, father, "parent", %{role: "father"})
    Ancestry.Relationships.create_relationship(grandmother, father, "parent", %{role: "mother"})

    grandson =
      insert(:person,
        given_name: "Mateo",
        surname: "Gendered",
        gender: "male",
        organization: family.organization
      )

    Ancestry.People.add_to_family(grandson, family)
    Ancestry.Relationships.create_relationship(father, grandson, "parent", %{role: "father"})

    %{
      family: family,
      org: org,
      grandfather: grandfather,
      grandmother: grandmother,
      grandson: grandson
    }
  end

  test "English — male grandparent to grandson shows 'Grandparent'", %{
    conn: conn,
    family: family,
    org: org,
    grandfather: grandfather,
    grandson: grandson
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects the male grandfather as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{grandfather.id}"))

    # And selects the grandson as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{grandson.id}"))

    # Then the relationship label shows "Grandparent" (English default, no gendered translation)
    conn
    |> assert_has(test_id("kinship-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Grandparent")
  end

  test "English — female grandparent to grandson shows 'Grandparent'", %{
    conn: conn,
    family: family,
    org: org,
    grandmother: grandmother,
    grandson: grandson
  } do
    # Given a logged-in user (default English locale)
    conn = log_in_e2e(conn)

    # When the user visits the kinship page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/kinship")
      |> wait_liveview()

    # And selects the female grandmother as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{grandmother.id}"))

    # And selects the grandson as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{grandson.id}"))

    # Then the relationship label also shows "Grandparent" (English has no gender distinction)
    conn
    |> assert_has(test_id("kinship-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Grandparent")
  end

  test "Spanish — male grandparent to grandson shows 'Abuelo'", %{
    conn: conn,
    family: family,
    org: org,
    grandfather: grandfather,
    grandson: grandson
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

    # And selects the male grandfather as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{grandfather.id}"))

    # And selects the grandson as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{grandson.id}"))

    # Then the label is the masculine Spanish translation "Abuelo"
    conn
    |> assert_has(test_id("kinship-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Abuelo")
  end

  test "Spanish — female grandparent to grandson shows 'Abuela'", %{
    conn: conn,
    family: family,
    org: org,
    grandmother: grandmother,
    grandson: grandson
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

    # And selects the female grandmother as Person A
    conn =
      conn
      |> click(test_id("kinship-person-a-toggle"))
      |> click(test_id("kinship-person-a-option-#{grandmother.id}"))

    # And selects the grandson as Person B
    conn =
      conn
      |> click(test_id("kinship-person-b-toggle"))
      |> click(test_id("kinship-person-b-option-#{grandson.id}"))

    # Then the label is the feminine Spanish translation "Abuela"
    conn
    |> assert_has(test_id("kinship-result"), timeout: 5_000)
    |> assert_has(test_id("kinship-relationship-label"), text: "Abuela")
  end
end
