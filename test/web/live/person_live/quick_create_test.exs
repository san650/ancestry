defmodule Web.PersonLive.QuickCreateTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person, org: org}
  end

  test "shows create new person link in add relationship modal", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    assert has_element?(view, "#start-quick-create-btn")
  end

  test "switches to quick create form when clicking create new", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    assert has_element?(view, "#quick-create-person")
    assert has_element?(view, "#quick-create-person-form")
    refute has_element?(view, "#relationship-search-input")
  end

  test "back to search returns to search view", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()
    assert has_element?(view, "#quick-create-person-form")

    view |> element("#cancel-quick-create-btn") |> render_click()
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#relationship-search-input")
  end

  test "validates given_name is required", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    html =
      view
      |> form("#quick-create-person-form", person: %{given_name: "", surname: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "creates person and proceeds to parent metadata step", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewDad", surname: "Smith"})
    |> render_submit()

    # Should now be on the metadata step (parent role form)
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#add-parent-form")
  end

  test "creates person and proceeds to partner metadata step", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-partner-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewWife", surname: "Jones"})
    |> render_submit()

    # Should now be on the metadata step (partner marriage form)
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#add-partner-form")
  end

  test "creates person and saves child relationship directly", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-child-solo-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewKid", surname: "Doe"})
    |> render_submit()

    # For child, it goes to the child confirm step
    assert has_element?(view, "#add-child-form")
  end

  test "new person is added to the family", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewMom", surname: "Lee"})
    |> render_submit()

    # Verify person was created in the family
    members = People.list_people_for_family(family.id)
    assert Enum.any?(members, &(&1.given_name == "NewMom" && &1.surname == "Lee"))
  end

  test "full flow: quick create parent then save relationship", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    # Open add parent modal
    view |> element("#add-parent-btn") |> render_click()

    # Switch to quick create
    view |> element("#start-quick-create-btn") |> render_click()

    # Create new person
    view
    |> form("#quick-create-person-form",
      person: %{given_name: "QuickDad", surname: "Fast"}
    )
    |> render_submit()

    # Now on metadata step — submit parent role form
    view |> form("#add-parent-form") |> render_submit()

    # Modal closed, relationship created
    refute has_element?(view, "#add-relationship-modal")
    assert render(view) =~ "QuickDad"
  end

  test "closing modal resets quick_creating state", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()
    assert has_element?(view, "#quick-create-person-form")

    # Reopen the modal (this triggers add_relationship which resets state)
    view |> element("#add-parent-btn") |> render_click()

    # Should be back to search, not quick create
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#relationship-search-input")
  end
end
