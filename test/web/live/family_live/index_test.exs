defmodule Web.FamilyLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    %{org: org}
  end

  test "lists all families", %{conn: conn, org: org} do
    {:ok, family} = Families.create_family(org, %{name: "The Smiths"})
    {:ok, _view, html} = live(conn, ~p"/org/#{org.id}")
    assert html =~ family.name
  end

  test "navigates to new family page", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

    expected_path = "/org/#{org.id}/families/new"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view |> element("#new-family-btn") |> render_click()
  end

  test "shows empty state when no families", %{conn: conn, org: org} do
    {:ok, _view, html} = live(conn, ~p"/org/#{org.id}")
    assert html =~ "No families yet"
  end

  test "deletes a family after confirmation", %{conn: conn, org: org} do
    {:ok, family} = Families.create_family(org, %{name: "To Delete"})
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

    view |> element("#delete-family-#{family.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    refute has_element?(view, "#family-#{family.id}")
  end
end
