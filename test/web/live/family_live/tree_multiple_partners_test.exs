defmodule Web.FamilyLive.TreeMultiplePartnersTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    {:ok, first_wife} =
      People.create_person(family, %{
        given_name: "Jane",
        surname: "Doe",
        gender: "female",
        deceased: true
      })

    {:ok, second_wife} =
      People.create_person(family, %{given_name: "Mary", surname: "Smith", gender: "female"})

    # First marriage (1985) — wife later died
    {:ok, _} =
      Relationships.create_relationship(person, first_wife, "married", %{marriage_year: 1985})

    # Second marriage (1995)
    {:ok, _} =
      Relationships.create_relationship(person, second_wife, "married", %{marriage_year: 1995})

    %{family: family, person: person, first_wife: first_wife, second_wife: second_wife, org: org}
  end

  describe "tree with multiple current partners" do
    test "shows both partners on the tree", %{
      conn: conn,
      family: family,
      person: person,
      first_wife: first_wife,
      second_wife: second_wife,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      # All three people should be visible via data-node-id
      assert has_element?(view, "[data-node-id='person-#{person.id}']")
      assert has_element?(view, "[data-node-id='person-#{second_wife.id}']")
      assert has_element?(view, "[data-node-id='person-#{first_wife.id}']")
    end

    test "latest partner appears in the graph", %{
      conn: conn,
      family: family,
      person: person,
      second_wife: second_wife,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      # The latest partner (second_wife) should appear as a node
      assert has_element?(view, "[data-node-id='person-#{second_wife.id}']")
      html = render(view)
      assert html =~ "Mary"
      assert html =~ "Smith"
    end

    test "previous partner appears in the graph", %{
      conn: conn,
      family: family,
      person: person,
      first_wife: first_wife,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      # Previous partner should also appear as a node
      assert has_element?(view, "[data-node-id='person-#{first_wife.id}']")
      html = render(view)
      assert html =~ "Jane"
    end

    test "children from both partners are visible", %{
      conn: conn,
      family: family,
      person: person,
      first_wife: first_wife,
      second_wife: second_wife,
      org: org
    } do
      # Add children for each partner
      {:ok, child_first} =
        People.create_person(family, %{given_name: "Alice", surname: "Doe", gender: "female"})

      {:ok, child_second} =
        People.create_person(family, %{given_name: "Bob", surname: "Smith", gender: "male"})

      {:ok, _} =
        Relationships.create_relationship(person, child_first, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(first_wife, child_first, "parent", %{role: "mother"})

      {:ok, _} =
        Relationships.create_relationship(person, child_second, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(second_wife, child_second, "parent", %{role: "mother"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      # Both children should be visible
      assert has_element?(view, "[data-node-id='person-#{child_first.id}']")
      assert has_element?(view, "[data-node-id='person-#{child_second.id}']")
    end
  end
end
