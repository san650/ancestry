defmodule Web.FamilyLive.TreeAddRelationshipTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person}
  end

  describe "add partner from tree" do
    test "shows add partner placeholder when no partner", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='partner']")
    end

    test "hides partner placeholder when partner exists", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, spouse} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

      {:ok, _} = Relationships.create_relationship(person, spouse, "married")

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "button[phx-value-type='partner']")
    end

    test "opens modal when clicking add partner placeholder", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "#add-relationship-modal")

      view |> element("button[phx-value-type='partner']") |> render_click()
      assert has_element?(view, "#add-relationship-modal")
      assert has_element?(view, "#relationship-search-input")
    end

    test "searches and adds a partner via modal", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Smith", gender: "female"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "Jan"})

      assert has_element?(view, "#search-result-#{candidate.id}")

      view |> element("#search-result-#{candidate.id}") |> render_click()
      assert has_element?(view, "#add-partner-form")

      view |> form("#add-partner-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "Jane"
    end

    test "quick creates a partner via modal", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      assert has_element?(view, "#quick-create-person-form")

      view
      |> form("#quick-create-person-form", person: %{given_name: "NewWife", surname: "Jones"})
      |> render_submit()

      assert has_element?(view, "#add-partner-form")

      view |> form("#add-partner-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "NewWife"
    end
  end

  describe "add child from tree" do
    test "shows add child placeholder when no children", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='child']")
    end

    test "opens modal and creates child", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='child']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      view
      |> form("#quick-create-person-form", person: %{given_name: "ChildName", surname: "Doe"})
      |> render_submit()

      assert has_element?(view, "#add-child-form")
      view |> form("#add-child-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "ChildName"
    end
  end

  describe "add parent from tree" do
    test "shows add parent placeholder when no parents", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='parent']")
    end

    test "hides parent placeholder when 2 parents exist", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, father} =
        People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

      {:ok, mother} =
        People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

      {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "button[phx-value-type='parent']")
    end

    test "opens modal and adds parent", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='parent']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      view
      |> form("#quick-create-person-form",
        person: %{given_name: "NewDad", surname: "Doe"}
      )
      |> render_submit()

      assert has_element?(view, "#add-parent-form")
      view |> form("#add-parent-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
    end
  end

  describe "modal behavior" do
    test "closes modal on backdrop click", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()
      assert has_element?(view, "#add-relationship-modal")

      render_click(view, "cancel_add_relationship")
      refute has_element?(view, "#add-relationship-modal")
    end

    test "keeps focus person after adding relationship", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "Jan"})

      view |> element("#search-result-#{candidate.id}") |> render_click()
      view |> form("#add-partner-form") |> render_submit()

      # Focus person should still be John
      assert has_element?(view, "#focus-person-card")
      html = render(view)
      assert html =~ "John"
    end
  end
end
