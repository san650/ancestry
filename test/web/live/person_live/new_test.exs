defmodule Web.PersonLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})
    %{family: family, org: org}
  end

  test "renders new person form", %{conn: conn, family: family, org: org} do
    {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")
    assert html =~ "New Member"
  end

  test "creates a person and redirects to family page", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane", surname: "Doe", gender: "female"})
    |> render_submit()

    assert_redirect(view, ~p"/org/#{org.id}/families/#{family.id}")
  end

  test "validates form on change", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane"})
    |> render_change()

    assert has_element?(view, "#person-form")
  end

  test "compact form shows only basic fields", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    # Basic fields visible
    assert has_element?(view, "#person_given_name")
    assert has_element?(view, "#person_surname")
    assert has_element?(view, "#add-more-details-btn")

    # Detail fields hidden
    refute has_element?(view, "#person_nickname")
    refute has_element?(view, "#person_title")
    refute has_element?(view, "#person-alternate-names")
  end

  test "clicking add more details expands the form", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    view |> element("#add-more-details-btn") |> render_click()

    assert has_element?(view, "#person_nickname")
    assert has_element?(view, "#person_title")
    assert has_element?(view, "#person_suffix")
    assert has_element?(view, "#person_given_name_at_birth")
    assert has_element?(view, "#person_surname_at_birth")
    assert has_element?(view, "#person-alternate-names")
    refute has_element?(view, "#add-more-details-btn")
  end

  test "birth date has day and month dropdowns", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    assert has_element?(view, "select#person_birth_day")
    assert has_element?(view, "select#person_birth_month")
    assert has_element?(view, "input#person_birth_year[type='number']")
  end

  test "gender field uses radio buttons", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    assert has_element?(view, "input[type='radio'][name='person[gender]'][value='female']")
    assert has_element?(view, "input[type='radio'][name='person[gender]'][value='male']")
    assert has_element?(view, "input[type='radio'][name='person[gender]'][value='other']")
  end

  test "living checkbox controls death date visibility", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

    # Living is checked by default, death date hidden
    refute has_element?(view, "select#person_death_day")

    # Uncheck living — death date should appear
    view
    |> form("#person-form")
    |> render_change(%{"person" => %{"living" => "false"}})

    assert has_element?(view, "select#person_death_day")
    assert has_element?(view, "select#person_death_month")
    assert has_element?(view, "input#person_death_year[type='number']")
  end
end
