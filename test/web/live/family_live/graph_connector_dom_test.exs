defmodule Web.FamilyLive.GraphConnectorDomTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup :register_and_log_in_account

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

  describe "graph canvas hook" do
    test "graph canvas has GraphConnector hook", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "#graph-canvas[phx-hook='GraphConnector']")
    end

    test "graph canvas has data-edges attribute with JSON", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      html = render(view)
      assert html =~ ~s(id="graph-canvas")
      assert html =~ "data-edges"
    end
  end

  describe "graph node data attributes" do
    test "person nodes have data-node-id attributes", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      parent_b: parent_b,
      child: child,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "[data-node-id='person-#{parent_a.id}']")
      assert has_element?(view, "[data-node-id='person-#{parent_b.id}']")
      assert has_element?(view, "[data-node-id='person-#{child.id}']")
    end

    test "focus person has data-focus='true'", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "[data-node-id='person-#{parent_a.id}'][data-focus='true']")
    end
  end

  describe "grid structure" do
    test "graph grid container exists", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      assert has_element?(view, "[data-graph-grid]")
    end

    test "graph renders person cards for all family members", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{parent_a.id}")

      render_async(view)
      html = render(view)
      assert html =~ "Parent A"
      assert html =~ "Parent B"
      assert html =~ "Child A"
    end
  end

  describe "no old hook references" do
    test "no BranchConnector, AncestorConnector, TreeConnector, or ScrollToFocus in rendered HTML",
         %{
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
      refute html =~ "TreeConnector"
    end
  end

  describe "no inline SVGs in graph" do
    test "graph has no old separator SVG elements", %{
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
end
