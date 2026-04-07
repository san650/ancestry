defmodule Web.PersonLive.RelationshipsTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person, org: org}
  end

  test "displays relationships section headings", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert has_element?(view, "#relationships-section")
    assert has_element?(view, "h3", "Spouses")
    assert has_element?(view, "h3", "Parents")
  end

  test "displays existing partner", %{conn: conn, family: family, person: person, org: org} do
    {:ok, spouse} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

    {:ok, _} =
      Relationships.create_relationship(person, spouse, "married", %{marriage_year: 2020})

    {:ok, view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert has_element?(view, "#partner-group-#{spouse.id}")
    assert html =~ "Jane"
    assert html =~ "2020"
  end

  test "displays existing parents with roles", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

    {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert html =~ "Dad"
    assert html =~ "Mom"
    assert html =~ "Father"
    assert html =~ "Mother"
  end

  test "displays children under partner group", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, spouse} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

    {:ok, _} =
      Relationships.create_relationship(person, spouse, "married", %{marriage_year: 2020})

    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(spouse, child, "parent", %{role: "mother"})

    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert html =~ "Kid"
  end

  test "displays solo children", %{conn: conn, family: family, person: person, org: org} do
    {:ok, child} =
      People.create_person(family, %{given_name: "Solo", surname: "Doe", gender: "female"})

    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})

    {:ok, view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert has_element?(view, "#solo-children-section")
    assert html =~ "Solo"
  end

  test "displays siblings from child perspective", %{conn: conn, family: family, org: org} do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "D", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "D", gender: "female"})

    {:ok, child1} =
      People.create_person(family, %{given_name: "Kid1", surname: "D", gender: "male"})

    {:ok, child2} =
      People.create_person(family, %{given_name: "Kid2", surname: "D", gender: "female"})

    {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

    {:ok, view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{child1.id}?from_family=#{family.id}")

    assert has_element?(view, "#siblings-section")
    assert html =~ "Kid2"
  end

  test "shows add parent button when fewer than 2 parents", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert has_element?(view, "#add-parent-btn")
  end

  test "hides add parent button when 2 parents exist", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "D", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "D", gender: "female"})

    {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    refute has_element?(view, "#add-parent-btn")
  end

  test "opens add parent modal", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    refute has_element?(view, "#add-relationship-modal")

    view |> element("#add-parent-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
    assert has_element?(view, "#add-rel-link-existing-btn")
    assert has_element?(view, "#add-rel-create-new-btn")

    view |> element("#add-rel-link-existing-btn") |> render_click()
    assert has_element?(view, "#relationship-search-input")
  end

  test "searches family members in add relationship modal", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, _candidate} =
      People.create_person(family, %{given_name: "Alice", surname: "Smith", gender: "female"})

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#add-rel-link-existing-btn") |> render_click()

    html = view |> element("#relationship-search-input") |> render_keyup(%{value: "Ali"})
    assert html =~ "Alice"
  end

  test "opens add partner modal", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-partner-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
  end

  test "opens add child solo modal", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-child-solo-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
  end

  test "displays ex-partner with divorce info", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, ex} =
      People.create_person(family, %{given_name: "Ex", surname: "Wife", gender: "female"})

    {:ok, _} =
      Relationships.create_relationship(person, ex, "divorced", %{
        marriage_year: 2010,
        divorce_year: 2015
      })

    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert html =~ "Ex"
    assert html =~ "2010"
    assert html =~ "2015"
  end

  test "displays children with unlinked co-parent", %{conn: conn, family: family, org: org} do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

    # Both are parents of child, but NOT linked as partners
    {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

    # Visit father's page — child should be visible in coparent section
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{father.id}?from_family=#{family.id}")

    assert has_element?(view, "#coparent-children-#{mother.id}")
    assert render(view) =~ "Kid"

    # Visit mother's page — child should also be visible
    {:ok, view2, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{mother.id}?from_family=#{family.id}")

    assert has_element?(view2, "#coparent-children-#{father.id}")
    assert render(view2) =~ "Kid"
  end

  test "child with partnered parents appears under partner group not coparent section", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, spouse} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

    {:ok, _} =
      Relationships.create_relationship(person, spouse, "married", %{marriage_year: 2020})

    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(spouse, child, "parent", %{role: "mother"})

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    # Child should be under partner group, NOT in coparent section
    assert has_element?(view, "#partner-group-#{spouse.id}")
    refute has_element?(view, "#coparent-children-#{spouse.id}")
    assert render(view) =~ "Kid"
  end

  test "selects a parent from search results and creates relationship", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, candidate} =
      People.create_person(family, %{given_name: "Alice", surname: "Smith", gender: "female"})

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    # Open add parent modal
    view |> element("#add-parent-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")

    # Choose link existing then search for candidate
    view |> element("#add-rel-link-existing-btn") |> render_click()
    view |> element("#relationship-search-input") |> render_keyup(%{value: "Ali"})
    assert has_element?(view, "#search-result-#{candidate.id}")

    # Click the search result — should select, not navigate
    view |> element("#search-result-#{candidate.id}") |> render_click()

    # Should still be on the same page with the selected person shown
    assert has_element?(view, "#add-relationship-modal")

    # Submit the relationship form (role is auto-set to "mother" for female)
    view |> form("#add-parent-form") |> render_submit()

    # Relationship created — modal closed, parent shown on page
    refute has_element?(view, "#add-relationship-modal")
    assert has_element?(view, "#parents-section")
    assert render(view) =~ "Alice"
  end
end
