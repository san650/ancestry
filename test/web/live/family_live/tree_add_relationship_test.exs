defmodule Web.FamilyLive.TreeAddRelationshipTest do
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

    %{family: family, person: person, org: org}
  end

  describe "add partner from tree" do
    test "opens modal via add_relationship event for partner", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      refute has_element?(view, "#add-relationship-modal")

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      assert has_element?(view, "#add-relationship-modal")
      assert has_element?(view, "#add-rel-link-existing-btn")
      assert has_element?(view, "#add-rel-create-new-btn")

      view |> element("#add-rel-link-existing-btn") |> render_click()
      assert has_element?(view, "#relationship-search-input")
    end

    test "searches and adds a partner via modal", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Smith", gender: "female"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      view |> element("#add-rel-link-existing-btn") |> render_click()

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
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      view |> element("#add-rel-create-new-btn") |> render_click()
      render(view)

      assert has_element?(view, "#quick-person-modal-form")

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "NewWife", surname: "Jones"}
      )
      |> render_submit()

      # Process the {:person_created, person} message forwarded via send_update
      render(view)

      assert has_element?(view, "#add-partner-form")

      view |> form("#add-partner-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "NewWife"
    end
  end

  describe "add child from tree" do
    test "opens modal and creates child", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "child", "person-id" => "#{person.id}"})
      view |> element("#add-rel-create-new-btn") |> render_click()
      render(view)

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "ChildName", surname: "Doe"}
      )
      |> render_submit()

      # Process the {:person_created, person} message forwarded via send_update
      render(view)

      assert has_element?(view, "#add-child-form")
      view |> form("#add-child-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "ChildName"
    end
  end

  describe "add parent from tree" do
    test "shows both parents in the graph when 2 parents exist", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, father} =
        People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

      {:ok, mother} =
        People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

      {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      assert has_element?(view, "[data-node-id='person-#{father.id}']")
      assert has_element?(view, "[data-node-id='person-#{mother.id}']")
    end

    test "opens modal and adds parent", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-create-new-btn") |> render_click()
      render(view)

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "NewDad", surname: "Doe"}
      )
      |> render_submit()

      # Process the {:person_created, person} message forwarded via send_update
      render(view)

      assert has_element?(view, "#add-parent-form")
      view |> form("#add-parent-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
    end
  end

  describe "modal behavior" do
    test "closes modal on backdrop click", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      assert has_element?(view, "#add-relationship-modal")

      render_click(view, "cancel_add_relationship")
      refute has_element?(view, "#add-relationship-modal")
    end

    test "keeps focus person after adding relationship", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      view |> element("#add-rel-link-existing-btn") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "Jan"})

      view |> element("#search-result-#{candidate.id}") |> render_click()
      view |> form("#add-partner-form") |> render_submit()

      # Focus person should still be John — identified by data-focus='true'
      assert has_element?(view, "[data-node-id='person-#{person.id}'][data-focus='true']")
      html = render(view)
      assert html =~ "John"
    end
  end

  describe "choose entry step" do
    # Given a family with at least one person
    # When the user opens the Add Parent modal
    # Then a Choose step is shown with two options: Link existing / Create new
    test "modal opens on the choose step with link/create options", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})

      assert has_element?(view, "#add-relationship-modal")
      assert has_element?(view, "#add-rel-link-existing-btn")
      assert has_element?(view, "#add-rel-create-new-btn")
      # Search input is NOT shown yet
      refute has_element?(view, "#relationship-search-input")
      refute has_element?(view, "#quick-person-modal-form")
    end

    # When the user clicks Link existing
    # Then the search step is shown with the search input
    test "clicking link existing shows the search step", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)

      render_click(view, "add_relationship", %{"type" => "partner", "person-id" => "#{person.id}"})

      view |> element("#add-rel-link-existing-btn") |> render_click()

      assert has_element?(view, "#relationship-search-input")
      assert has_element?(view, "#add-rel-back-to-choose-from-search-btn")
    end

    # When the user clicks Back from the search step
    # Then the Choose step is shown again
    # And the search query state is cleared
    test "back from search returns to choose and clears state", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Alice", surname: "Smith", gender: "female"})

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-link-existing-btn") |> render_click()

      view |> element("#relationship-search-input") |> render_keyup(%{value: "Ali"})
      assert has_element?(view, "#search-result-#{candidate.id}")

      view |> element("#add-rel-back-to-choose-from-search-btn") |> render_click()

      # Choose step shown again
      assert has_element?(view, "#add-rel-link-existing-btn")
      assert has_element?(view, "#add-rel-create-new-btn")
      refute has_element?(view, "#relationship-search-input")

      # Re-enter the search step — previous query and results should be cleared
      view |> element("#add-rel-link-existing-btn") |> render_click()
      assert has_element?(view, "#relationship-search-input")
      refute has_element?(view, "#search-result-#{candidate.id}")
    end

    # When the user clicks Create new from the Choose step
    # Then the quick-create form is shown with empty fields
    test "clicking create new shows the quick-create modal at LiveView level", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-create-new-btn") |> render_click()
      render(view)

      assert has_element?(view, "#quick-person-modal-form")
      refute has_element?(view, "#relationship-search-input")
    end

    # When the user cancels the quick-create modal
    # Then the Choose step is shown again
    test "cancelling quick-create returns to choose step", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-create-new-btn") |> render_click()
      render(view)

      assert has_element?(view, "#quick-person-modal-form")

      # Cancel the quick create modal — sends {:quick_person_cancelled} to parent
      send(view.pid, {:quick_person_cancelled})
      render(view)

      # Choose step shown again
      assert has_element?(view, "#add-rel-link-existing-btn")
      assert has_element?(view, "#add-rel-create-new-btn")
      refute has_element?(view, "#quick-person-modal-form")
    end
  end

  describe "auto-set gender from parent role" do
    test "sets gender to male when adding parent with role father and person has no gender", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "NoGender", surname: "Parent"})

      assert candidate.gender == nil

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-link-existing-btn") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "NoGender"})

      view |> element("#search-result-#{candidate.id}") |> render_click()

      view
      |> form("#add-parent-form", metadata: %{role: "father"})
      |> render_submit()

      updated = People.get_person!(candidate.id)
      assert updated.gender == "male"
    end

    test "sets gender to female when adding parent with role mother and person has no gender", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "NoGender2", surname: "Parent"})

      assert candidate.gender == nil

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-link-existing-btn") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "NoGender2"})

      view |> element("#search-result-#{candidate.id}") |> render_click()

      view
      |> form("#add-parent-form", metadata: %{role: "mother"})
      |> render_submit()

      updated = People.get_person!(candidate.id)
      assert updated.gender == "female"
    end

    test "does not overwrite existing gender when adding parent", %{
      conn: conn,
      family: family,
      person: person,
      org: org
    } do
      {:ok, candidate} =
        People.create_person(family, %{
          given_name: "HasGender",
          surname: "Parent",
          gender: "female"
        })

      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.id}/families/#{family.id}?person=#{person.id}")

      render_async(view)
      render_click(view, "add_relationship", %{"type" => "parent", "person-id" => "#{person.id}"})
      view |> element("#add-rel-link-existing-btn") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "HasGender"})

      view |> element("#search-result-#{candidate.id}") |> render_click()

      view
      |> form("#add-parent-form", metadata: %{role: "father"})
      |> render_submit()

      updated = People.get_person!(candidate.id)
      assert updated.gender == "female"
    end
  end
end
