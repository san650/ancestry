defmodule Web.FamilyLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "shows family name", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ family.name
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
