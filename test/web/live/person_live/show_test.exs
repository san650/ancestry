defmodule Web.PersonLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{
        given_name: "Jane",
        surname: "Doe",
        gender: "female",
        deceased: false
      })

    %{family: family, person: person, org: org}
  end

  test "shows person details", %{conn: conn, family: family, person: person, org: org} do
    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert html =~ "Jane"
    assert html =~ "Doe"
  end

  test "edits person name", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#edit-person-btn") |> render_click()

    view
    |> form("#person-form", person: %{given_name: "Janet"})
    |> render_submit()

    assert render(view) =~ "Janet"
  end

  test "edit form auto-expands when person has extra fields", %{
    conn: conn,
    family: family,
    org: org
  } do
    {:ok, person_with_nickname} =
      People.create_person(family, %{
        given_name: "Maria",
        surname: "Silva",
        nickname: "Mari",
        gender: "female"
      })

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person_with_nickname.id}?from_family=#{family.id}")

    view |> element("#edit-person-btn") |> render_click()

    # Form should be auto-expanded since nickname has a value
    assert has_element?(view, "#person_nickname")
    refute has_element?(view, "#add-more-details-btn")
  end

  test "edit form shows compact when person has only basic fields", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#edit-person-btn") |> render_click()

    # Person only has given_name, surname, gender — should be compact
    assert has_element?(view, "#add-more-details-btn")
    refute has_element?(view, "#person_nickname")
  end

  test "shows deceased status on detail page", %{conn: conn, family: family, org: org} do
    {:ok, deceased_person} =
      People.create_person(family, %{
        given_name: "John",
        surname: "Doe",
        deceased: true,
        death_year: 1994
      })

    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{deceased_person.id}?from_family=#{family.id}")

    assert html =~ "d. 1994"
    refute html =~ "Deceased:"
  end

  test "shows deceased indicator on person card for related people", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    {:ok, deceased_parent} =
      People.create_person(family, %{
        given_name: "John",
        surname: "Doe",
        deceased: true,
        death_year: 1994
      })

    Ancestry.Relationships.create_relationship(deceased_parent, person, "parent", %{
      role: "father"
    })

    {:ok, _view, html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    assert html =~ "d. 1994"
    assert html =~ "This person is deceased."
  end

  test "removes person from family", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#remove-from-family-btn") |> render_click()
    view |> element("#confirm-remove-btn") |> render_click()
    assert_redirect(view, ~p"/org/#{org.id}/families/#{family.id}")
  end

  test "deletes person permanently", %{conn: conn, family: family, person: person, org: org} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

    view |> element("#delete-person-btn") |> render_click()
    assert has_element?(view, "#confirm-delete-person-modal")

    view |> element("#confirm-delete-btn") |> render_click()
    assert_redirect(view, ~p"/org/#{org.id}/families/#{family.id}")

    assert_raise Ecto.NoResultsError, fn -> People.get_person!(person.id) end
  end

  test "removes person photo from edit form", %{
    conn: conn,
    family: family,
    person: person,
    org: org
  } do
    # Given a person with a processed photo
    {:ok, person_with_photo} =
      person
      |> Ecto.Changeset.change(%{
        photo: %{file_name: "test.jpg", updated_at: nil},
        photo_status: "processed"
      })
      |> Ancestry.Repo.update()

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/people/#{person_with_photo.id}?from_family=#{family.id}")

    # When the user clicks edit and then remove photo
    view |> element("#edit-person-btn") |> render_click()
    assert has_element?(view, "#remove-photo-btn")

    view |> element("#remove-photo-btn") |> render_click()

    # Then the photo is removed and the remove button is gone
    refute has_element?(view, "#remove-photo-btn")

    # And the DB is updated
    updated = People.get_person!(person.id)
    assert is_nil(updated.photo)
    assert is_nil(updated.photo_status)
  end
end
