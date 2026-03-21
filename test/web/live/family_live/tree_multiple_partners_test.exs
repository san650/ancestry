defmodule Web.FamilyLive.TreeMultiplePartnersTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

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

      # All three people should be visible
      assert has_element?(view, "[data-person-id='#{person.id}']")
      assert has_element?(view, "[data-person-id='#{second_wife.id}']")
      assert has_element?(view, "[data-person-id='#{first_wife.id}']")
    end

    test "latest partner is in the main couple position", %{
      conn: conn,
      family: family,
      person: person,
      second_wife: second_wife,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      # The couple card should have the latest partner (second_wife) as person_b
      assert has_element?(
               view,
               "[data-couple-card][data-person-b-id='#{second_wife.id}']"
             )
    end

    test "previous partner has solid separator line, not dashed", %{
      conn: conn,
      family: family,
      person: person,
      first_wife: first_wife,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      # Previous partner should have a solid separator (data-previous-separator)
      assert has_element?(view, "[data-previous-separator='#{first_wife.id}']")
      # Should NOT have a dashed ex-separator
      refute has_element?(view, "[data-ex-separator='#{first_wife.id}']")
    end

    test "children from previous partner have correct line_origin attribute", %{
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

      # Both children should be visible
      assert has_element?(view, "[data-person-id='#{child_first.id}']")
      assert has_element?(view, "[data-person-id='#{child_second.id}']")

      # Child of previous partner should have prev- line origin for BranchConnector
      assert has_element?(view, "[data-line-origin='prev-#{first_wife.id}']")
      # Child of current partner should have partner line origin
      assert has_element?(view, "[data-line-origin='partner']")
      # Previous partner separator should exist for connector JS hook
      assert has_element?(view, "[data-previous-separator='#{first_wife.id}']")
    end
  end
end
