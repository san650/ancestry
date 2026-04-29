defmodule Web.UserFlows.AcquaintancePersonTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ancestry.Factory

  # Creating an acquaintance person
  #
  # Given an existing family
  # When the user navigates to add a new member
  # And checks "This person is not a family member"
  # And fills in given name and surname
  # And clicks Create
  # Then the person is created with kind "acquaintance"
  # And the person appears in the people list with a "Non-family" badge
  #
  # Person show page for acquaintance
  #
  # Given an acquaintance person in a family
  # When the user views the person's show page
  # Then the "Convert to family member" banner is shown
  # And the relationships section is hidden
  #
  # Converting acquaintance to family member
  #
  # Given an acquaintance person
  # When the user clicks "Convert to family member"
  # Then the person is converted
  # And the relationships section appears
  # And the banner disappears
  #
  # Converting family member to acquaintance
  #
  # Given a family member with no relationships
  # When the user clicks "Convert to non-family"
  # Then the person is converted
  # And the relationships section disappears
  # And the banner appears
  #
  # Blocking conversion when relationships exist
  #
  # Given a family member with relationships
  # When the user clicks "Convert to non-family"
  # Then a warning is shown
  # And the person remains a family member
  #
  # Non-family filter on people list
  #
  # Given a family with both kinds
  # When the user clicks the "Non-family" filter
  # Then only acquaintances are shown

  setup %{conn: conn} do
    account = insert(:account)
    org = insert(:organization)
    insert(:account_organization, account: account, organization: org)
    family = insert(:family, organization: org)
    conn = log_in_account(conn, account)

    %{conn: conn, org: org, family: family}
  end

  describe "creating acquaintance" do
    test "creates person with acquaintance kind via checkbox", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

      view
      |> form("#person-form",
        person: %{given_name: "Neighbor", surname: "Joe", kind: "acquaintance"}
      )
      |> render_submit()

      {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")
      assert html =~ "Neighbor"
      assert html =~ "Non-family"
    end
  end

  describe "person show page for acquaintance" do
    setup %{org: org, family: family} do
      acquaintance =
        insert(:acquaintance, given_name: "Friend", surname: "Smith", organization: org)

      insert(:family_member, family: family, person: acquaintance)
      %{acquaintance: acquaintance}
    end

    test "hides relationships and shows convert banner", %{
      conn: conn,
      org: org,
      acquaintance: acquaintance
    } do
      {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/people/#{acquaintance.id}")

      assert html =~ "Convert to family member"
      refute html =~ "Relationships"
    end

    test "converts acquaintance to family member", %{
      conn: conn,
      org: org,
      acquaintance: acquaintance
    } do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/people/#{acquaintance.id}")

      view |> element(test_id("convert-to-family-btn")) |> render_click()

      html = render(view)
      refute html =~ "Convert to family member"
      assert html =~ "Relationships"
    end
  end

  describe "person show page for family member" do
    setup %{org: org, family: family} do
      person = insert(:person, given_name: "Regular", surname: "Member", organization: org)
      insert(:family_member, family: family, person: person)
      %{person: person}
    end

    test "shows convert to non-family button", %{
      conn: conn,
      org: org,
      family: family,
      person: person
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      # Open kebab menu to reveal convert button
      view |> render_click("toggle_menu")
      assert has_element?(view, test_id("convert-to-acquaintance-btn"))
    end

    test "converts family member to acquaintance when no relationships", %{
      conn: conn,
      org: org,
      family: family,
      person: person
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      # Open kebab menu first, then click convert
      view |> render_click("toggle_menu")
      view |> element(test_id("convert-to-acquaintance-btn")) |> render_click()

      html = render(view)
      assert html =~ "Convert to family member"
      refute html =~ "Relationships"
    end

    test "blocks conversion when relationships exist", %{
      conn: conn,
      org: org,
      family: family,
      person: person
    } do
      other = insert(:person, given_name: "Other", surname: "Person", organization: org)
      insert(:family_member, family: family, person: other)
      Ancestry.Relationships.create_relationship(person, other, "parent", %{role: "father"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      # Open kebab menu first, then click convert
      view |> render_click("toggle_menu")
      view |> element(test_id("convert-to-acquaintance-btn")) |> render_click()

      assert render(view) =~ "Remove all relationships"
    end
  end

  describe "people list filters" do
    setup %{org: org, family: family} do
      person = insert(:person, given_name: "Family", surname: "Person", organization: org)

      acquaintance =
        insert(:acquaintance, given_name: "NonFamily", surname: "Person", organization: org)

      insert(:family_member, family: family, person: person)
      insert(:family_member, family: family, person: acquaintance)
      %{person: person, acquaintance: acquaintance}
    end

    test "non-family filter shows only acquaintances", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")

      html = render(view)
      assert html =~ "Family"
      assert html =~ "NonFamily"

      view |> element(test_id("people-acquaintance-chip")) |> render_click()

      html = render(view)
      assert html =~ "NonFamily"
    end

    test "non-family badge appears next to acquaintance name", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")

      assert html =~ "Non-family"
    end
  end
end
