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
        living: "yes"
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

  test "removes person from family", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#remove-from-family-btn") |> render_click()
    view |> element("#confirm-remove-btn") |> render_click()
    assert_redirect(view, ~p"/families/#{family.id}/members")
  end

  test "deletes person permanently", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#delete-person-btn") |> render_click()
    assert has_element?(view, "#confirm-delete-person-modal")

    view |> element("#confirm-delete-btn") |> render_click()
    assert_redirect(view, ~p"/families/#{family.id}/members")

    assert_raise Ecto.NoResultsError, fn -> People.get_person!(person.id) end
  end
end
