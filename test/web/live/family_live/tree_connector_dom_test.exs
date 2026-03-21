defmodule Web.FamilyLive.TreeConnectorDomTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Connector Test Family"})

    {:ok, parent_a} =
      People.create_person(family, %{given_name: "Parent", surname: "A", gender: "male"})

    {:ok, parent_b} =
      People.create_person(family, %{given_name: "Parent", surname: "B", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Child", surname: "A", gender: "male"})

    {:ok, _} = Relationships.create_relationship(parent_a, parent_b, "married", %{})
    {:ok, _} = Relationships.create_relationship(parent_a, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent_b, child, "parent", %{role: "mother"})

    %{family: family, parent_a: parent_a, parent_b: parent_b, child: child, org: org}
  end

  describe "tree canvas hook" do
    test "tree canvas has TreeConnector hook", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "#tree-canvas[phx-hook='TreeConnector']")
    end

    test "tree canvas has relative positioning class", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert html =~ ~s(id="tree-canvas")
      assert html =~ "relative"
    end
  end

  describe "couple card data attributes" do
    test "couple card retains data attributes", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      parent_b: parent_b,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "[data-couple-card][data-person-a-id='#{parent_a.id}']")
      assert has_element?(view, "[data-couple-card][data-person-b-id='#{parent_b.id}']")
    end
  end

  describe "children row data attributes" do
    test "child columns retain line origin and person id", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      child: child,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "[data-child-column][data-child-person-id='#{child.id}']")
      assert has_element?(view, "[data-line-origin='partner']")
    end
  end

  describe "no old hook references" do
    test "no BranchConnector, AncestorConnector, or ScrollToFocus in rendered HTML", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      refute html =~ "BranchConnector"
      refute html =~ "AncestorConnector"
      refute html =~ "ScrollToFocus"
    end
  end

  describe "no inline SVGs in couple cards" do
    test "couple card has no separator SVG elements", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      # The old inline SVGs had viewBox="0 0 40 123" - these should be gone
      refute html =~ "viewBox=\"0 0 40 123\""
    end
  end

  describe "ex-partner separator spacers" do
    setup %{family: family, parent_a: parent_a} do
      {:ok, ex} =
        People.create_person(family, %{given_name: "Ex", surname: "Partner", gender: "female"})

      {:ok, _} = Relationships.create_relationship(parent_a, ex, "divorced", %{})

      %{ex: ex}
    end

    test "ex-partner separator is a div, not an svg", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      ex: ex,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "div[data-ex-separator='#{ex.id}']")
      refute has_element?(view, "svg[data-ex-separator='#{ex.id}']")
    end
  end
end
