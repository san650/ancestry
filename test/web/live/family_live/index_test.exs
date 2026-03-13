defmodule Web.FamilyLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  test "lists all families", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "The Smiths"})
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ family.name
  end

  test "navigates to new family page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/families/new"}}} =
             view |> element("#new-family-btn") |> render_click()
  end

  test "shows empty state when no families", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "No families yet"
  end

  test "deletes a family after confirmation", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "To Delete"})
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#delete-family-#{family.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    refute has_element?(view, "#family-#{family.id}")
  end
end
