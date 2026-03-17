defmodule Web.PersonLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{
        given_name: "Jane",
        surname: "Doe",
        gender: "female",
        deceased: false
      })

    %{family: family, person: person}
  end

  test "shows person details", %{conn: conn, family: family, person: person} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Jane"
    assert html =~ "Doe"
  end

  test "edits person name", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#edit-person-btn") |> render_click()

    view
    |> form("#edit-person-form", person: %{given_name: "Janet"})
    |> render_submit()

    assert render(view) =~ "Janet"
  end

  test "shows deceased status on detail page", %{conn: conn, family: family} do
    {:ok, deceased_person} =
      People.create_person(family, %{
        given_name: "John",
        surname: "Doe",
        deceased: true,
        death_year: 1994
      })

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{deceased_person.id}")
    assert html =~ "Deceased:"
    assert html =~ "Yes"
  end

  test "shows deceased indicator on person card for related people", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, deceased_parent} =
      People.create_person(family, %{
        given_name: "John",
        surname: "Doe",
        deceased: true,
        death_year: 1994
      })

    Ancestry.Relationships.create_relationship(deceased_parent, person, "parent", %{
      role: "father"
    })

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "d. 1994"
    assert html =~ "This person is deceased."
  end

  test "removes person from family", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#remove-from-family-btn") |> render_click()
    view |> element("#confirm-remove-btn") |> render_click()
    assert_redirect(view, ~p"/families/#{family.id}")
  end

  test "deletes person permanently", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#delete-person-btn") |> render_click()
    assert has_element?(view, "#confirm-delete-person-modal")

    view |> element("#confirm-delete-btn") |> render_click()
    assert_redirect(view, ~p"/families/#{family.id}")

    assert_raise Ecto.NoResultsError, fn -> People.get_person!(person.id) end
  end
end
