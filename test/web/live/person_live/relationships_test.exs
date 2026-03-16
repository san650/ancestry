defmodule Web.PersonLive.RelationshipsTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person}
  end

  test "displays relationships section headings", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert has_element?(view, "#relationships-section")
    assert has_element?(view, "h3", "Spouses")
    assert has_element?(view, "h3", "Parents")
  end

  test "displays existing partner", %{conn: conn, family: family, person: person} do
    {:ok, spouse} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

    {:ok, _} =
      Relationships.create_relationship(person, spouse, "partner", %{marriage_year: 2020})

    {:ok, view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert has_element?(view, "#partner-group-#{spouse.id}")
    assert html =~ "Jane"
    assert html =~ "2020"
  end

  test "displays existing parents with roles", %{conn: conn, family: family, person: person} do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

    {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Dad"
    assert html =~ "Mom"
    assert html =~ "Father"
    assert html =~ "Mother"
  end

  test "displays children under partner group", %{conn: conn, family: family, person: person} do
    {:ok, spouse} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

    {:ok, _} =
      Relationships.create_relationship(person, spouse, "partner", %{marriage_year: 2020})

    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(spouse, child, "parent", %{role: "mother"})

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Kid"
  end

  test "displays solo children", %{conn: conn, family: family, person: person} do
    {:ok, child} =
      People.create_person(family, %{given_name: "Solo", surname: "Doe", gender: "female"})

    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})

    {:ok, view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert has_element?(view, "#solo-children-section")
    assert html =~ "Solo"
  end

  test "displays siblings from child perspective", %{conn: conn, family: family} do
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

    {:ok, view, html} = live(conn, ~p"/families/#{family.id}/members/#{child1.id}")
    assert has_element?(view, "#siblings-section")
    assert html =~ "Kid2"
  end

  test "shows add parent button when fewer than 2 parents", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert has_element?(view, "#add-parent-btn")
  end

  test "hides add parent button when 2 parents exist", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "D", gender: "male"})

    {:ok, mother} =
      People.create_person(family, %{given_name: "Mom", surname: "D", gender: "female"})

    {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    refute has_element?(view, "#add-parent-btn")
  end

  test "opens add parent modal", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    refute has_element?(view, "#add-relationship-modal")

    view |> element("#add-parent-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
    assert has_element?(view, "#relationship-search-input")
  end

  test "searches family members in add relationship modal", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, _candidate} =
      People.create_person(family, %{given_name: "Alice", surname: "Smith", gender: "female"})

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()

    html = view |> element("#relationship-search-input") |> render_keyup(%{value: "Ali"})
    assert html =~ "Alice"
  end

  test "opens add partner modal", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-partner-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
  end

  test "opens add child solo modal", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-child-solo-btn") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
  end

  test "displays ex-partner with divorce info", %{conn: conn, family: family, person: person} do
    {:ok, ex} =
      People.create_person(family, %{given_name: "Ex", surname: "Wife", gender: "female"})

    {:ok, _} =
      Relationships.create_relationship(person, ex, "ex_partner", %{
        marriage_year: 2010,
        divorce_year: 2015
      })

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Ex"
    assert html =~ "2010"
    assert html =~ "2015"
  end
end
