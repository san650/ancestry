defmodule Web.PersonLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "renders new person form", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/new")
    assert html =~ "New Member"
  end

  test "creates a person and redirects to family page", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane", surname: "Doe", gender: "female"})
    |> render_submit()

    assert_redirect(view, ~p"/families/#{family.id}")
  end

  test "validates form on change", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane"})
    |> render_change()

    assert has_element?(view, "#person-form")
  end
end
