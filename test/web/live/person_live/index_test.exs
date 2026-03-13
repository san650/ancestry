defmodule Web.PersonLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "lists family members", %{conn: conn, family: family} do
    {:ok, _person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members")
    assert html =~ "Jane Doe"
  end

  test "shows empty state when no members", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members")
    assert html =~ "No members yet"
  end

  test "has add member button", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members")
    assert has_element?(view, "#add-member-btn")
  end
end
