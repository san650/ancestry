defmodule Web.FamilyLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.People

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})
    %{family: family, org: org}
  end

  test "shows family name", %{conn: conn, family: family, org: org} do
    {:ok, view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    assert html =~ family.name
  end

  test "shows family members in side panel", %{conn: conn, family: family, org: org} do
    {:ok, _} =
      People.create_person(family, %{given_name: "Jane", surname: "Doe", birth_year: 1985})

    {:ok, view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    assert html =~ "Doe"
    assert html =~ "Jane"
    assert html =~ "Select a person"
    assert has_element?(view, "#person-selector-center")
  end

  test "shows family galleries", %{conn: conn, family: family, org: org} do
    insert(:gallery, name: "Summer 2025", family: family)
    {:ok, view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    assert html =~ "Summer 2025"
  end

  test "shows empty states when no members or galleries", %{conn: conn, family: family, org: org} do
    {:ok, view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    assert html =~ "No members yet"
    assert html =~ "No galleries yet"
  end

  test "updates family name", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    render_click(view, "edit")

    view
    |> form("#edit-family-form", family: %{name: "Updated Name"})
    |> render_submit()

    assert render(view) =~ "Updated Name"
  end

  test "deletes family and redirects to index", %{conn: conn, family: family, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
    render_async(view)
    render_click(view, "request_delete")
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    assert_redirect(view, ~p"/org/#{org.id}")
  end

  describe "gallery management" do
    test "opens new gallery modal", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)
      refute has_element?(view, "#new-gallery-modal")
      view |> element("#side-panel-desktop-gallery-list-new-btn") |> render_click()
      assert has_element?(view, "#new-gallery-modal")
    end

    test "creates a gallery via the new gallery modal", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)
      view |> element("#side-panel-desktop-gallery-list-new-btn") |> render_click()

      view
      |> form("#new-gallery-form", gallery: %{name: "Winter 2025"})
      |> render_submit()

      assert has_element?(view, "[data-gallery-name]", "Winter 2025")
    end

    test "shows validation error for blank gallery name", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)
      view |> element("#side-panel-desktop-gallery-list-new-btn") |> render_click()

      view
      |> form("#new-gallery-form", gallery: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#new-gallery-form .text-cm-error")
    end

    test "deletes a gallery after confirmation", %{conn: conn, family: family, org: org} do
      gallery = insert(:gallery, name: "To Delete", family: family)
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      # Gallery is shown in the side panel list
      assert has_element?(view, "#side-panel-desktop-gallery-list-#{gallery.id}")

      # The gallery list no longer has inline delete buttons.
      # Test the gallery modal flow for deletion instead.
      # We still have the request_delete_gallery event, so trigger it directly.
      render_click(view, "request_delete_gallery", %{"id" => "#{gallery.id}"})
      assert has_element?(view, "#confirm-delete-gallery-modal")

      view
      |> element("#confirm-delete-gallery-modal [phx-click='confirm_delete_gallery']")
      |> render_click()

      refute has_element?(view, "#side-panel-desktop-gallery-list-#{gallery.id}")
    end
  end

  describe "link existing person" do
    setup %{family: _family, org: org} do
      {:ok, other_family} = Families.create_family(org, %{name: "Other Family"})

      {:ok, person} =
        People.create_person(other_family, %{given_name: "Ignacio", surname: "Ruiz"})

      %{person: person}
    end

    test "opens search modal", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      refute has_element?(view, "#link-person-modal")

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()

      assert has_element?(view, "#link-person-modal")
      assert has_element?(view, "#person-search-input")
    end

    test "searches for people by name", %{conn: conn, family: family, org: org, person: person} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()

      render_keyup(view, "search", %{"key" => "o", "value" => "Ign"})

      assert has_element?(view, "#link-person-#{person.id}")
    end

    test "links person to family", %{conn: conn, family: family, org: org, person: person} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()
      render_keyup(view, "search", %{"key" => "o", "value" => "Ignacio"})

      view |> element("#link-person-#{person.id}") |> render_click()

      refute has_element?(view, "#link-person-modal")
      # Person now appears in the people list sidebar
      html = render(view)
      assert html =~ "Ignacio"
      assert html =~ "Ruiz"
    end

    test "closes search modal", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()
      assert has_element?(view, "#link-person-modal")

      view |> element("button", "Cancel") |> render_click()
      refute has_element?(view, "#link-person-modal")
    end

    test "excludes people already in the family from search results", %{
      conn: conn,
      family: family,
      org: org
    } do
      {:ok, member} = People.create_person(family, %{given_name: "Ignacio", surname: "Familiar"})

      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()
      render_keyup(view, "search", %{"key" => "o", "value" => "Ignacio"})

      refute has_element?(view, "#link-person-#{member.id}")
    end

    test "does not search with fewer than 2 characters", %{conn: conn, family: family, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")
      render_async(view)

      view |> element("#side-panel-desktop-people-list-link-btn") |> render_click()
      render_keyup(view, "search", %{"key" => "I", "value" => "I"})

      refute has_element?(view, "button[phx-click=link_person]")
    end
  end
end
