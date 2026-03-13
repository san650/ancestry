defmodule Web.FamilyLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  test "renders new family form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/families/new")
    assert html =~ "New Family"
    assert html =~ "new-family-form"
  end

  test "creates a family with valid name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/families/new")

    view
    |> form("#new-family-form", family: %{name: "The Johnsons"})
    |> render_submit()

    [family] = Families.list_families()
    assert family.name == "The Johnsons"
  end

  test "shows validation error for blank name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/families/new")

    view
    |> form("#new-family-form", family: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-family-form .text-error")
  end
end
