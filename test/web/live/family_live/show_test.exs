defmodule Web.FamilyLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "shows family name", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ family.name
  end

  test "shows family members", %{conn: conn, family: family} do
    {:ok, _} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", birth_year: 1985})

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ "Jane Doe"
    assert html =~ "1985"
  end

  test "shows family galleries", %{conn: conn, family: family} do
    {:ok, _} = Galleries.create_gallery(%{name: "Summer 2025", family_id: family.id})
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ "Summer 2025"
  end

  test "shows empty states when no members or galleries", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ "No members yet"
    assert html =~ "No galleries yet"
  end

  test "updates family name", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}")
    view |> element("#edit-family-btn") |> render_click()

    view
    |> form("#edit-family-form", family: %{name: "Updated Name"})
    |> render_submit()

    assert render(view) =~ "Updated Name"
  end

  test "deletes family and redirects to index", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}")
    view |> element("#delete-family-btn") |> render_click()
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    assert_redirect(view, ~p"/")
  end
end
