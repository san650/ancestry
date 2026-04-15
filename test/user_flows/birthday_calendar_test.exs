defmodule Web.UserFlows.BirthdayCalendarTest do
  @moduledoc """
  Birthday calendar flow

  Given a family with people who have birth dates
  When the user navigates to the birthday calendar from the family meatball menu
  Then a vertical calendar is shown with months January through December
  And people are listed under their birth month ordered by day
  And a "TODAY" marker divides past from upcoming birthdays
  And deceased people are tagged with "(deceased)"
  And people without birth month/day are excluded
  And clicking a person navigates to their profile
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Birthday Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    # Person with birthday in January (past, assuming test runs after Jan)
    jan_person =
      insert(:person,
        given_name: "January",
        surname: "Person",
        birth_month: 1,
        birth_day: 15,
        birth_year: 1990,
        organization: family.organization
      )

    Ancestry.People.add_to_family(jan_person, family)

    # Deceased person with birthday in March
    deceased_person =
      insert(:person,
        given_name: "March",
        surname: "Deceased",
        birth_month: 3,
        birth_day: 20,
        birth_year: 1940,
        deceased: true,
        organization: family.organization
      )

    Ancestry.People.add_to_family(deceased_person, family)

    # Person with birthday in December (future)
    dec_person =
      insert(:person,
        given_name: "December",
        surname: "Person",
        birth_month: 12,
        birth_day: 25,
        birth_year: 2000,
        organization: family.organization
      )

    Ancestry.People.add_to_family(dec_person, family)

    # Person without complete birth date (excluded)
    no_birthday =
      insert(:person,
        given_name: "NoBirthday",
        surname: "Person",
        birth_month: nil,
        birth_day: nil,
        organization: family.organization
      )

    Ancestry.People.add_to_family(no_birthday, family)

    %{
      family: family,
      org: org,
      jan_person: jan_person,
      deceased_person: deceased_person,
      dec_person: dec_person,
      no_birthday: no_birthday
    }
  end

  test "view birthday calendar from family menu", %{
    conn: conn,
    family: family,
    org: org,
    jan_person: jan_person,
    deceased_person: deceased_person,
    dec_person: dec_person,
    no_birthday: no_birthday
  } do
    conn =
      conn
      |> log_in_e2e(organization_ids: [org.id])
      |> PhoenixTest.visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Open meatball menu and click birthdays
    conn =
      conn
      |> click(test_id("meatball-btn"))
      |> click(test_id("family-birthdays-btn"))
      |> wait_liveview()

    # All 12 months are shown
    conn
    |> assert_has("span", text: "January")
    |> assert_has("span", text: "December")

    # Empty month placeholder
    |> assert_has("p", text: "No birthdays")

    # January person shown
    |> assert_has(test_id("birthday-entry-#{jan_person.id}"), text: "January Person")

    # Deceased tagged
    |> assert_has(test_id("birthday-entry-#{deceased_person.id}"), text: "deceased")

    # December person shown
    |> assert_has(test_id("birthday-entry-#{dec_person.id}"), text: "December Person")

    # NoBirthday person excluded
    |> refute_has(test_id("birthday-entry-#{no_birthday.id}"))

    # Today marker is present
    |> assert_has("#today-marker")

    # Click a person navigates to their profile
    conn
    |> click(test_id("birthday-entry-#{dec_person.id}"))
    |> wait_liveview()
    |> assert_has("h1", text: "December Person")
  end
end
