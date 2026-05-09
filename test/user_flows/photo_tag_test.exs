defmodule Web.UserFlows.PhotoTagTest do
  @moduledoc """
  Verifies tag/untag/upsert flows dispatch through `Ancestry.Bus` and
  write audit rows.

  ## Scenarios

  ### Tag person with coords

  Given an admin viewing a gallery with a processed photo
  When the user dispatches a tag with coords
  Then a photo_person row is created
  And an audit_log row is written for `Ancestry.Commands.TagPersonInPhoto`

  ### Re-tag updates coordinates (upsert)

  Given an existing tag for the same (photo, person)
  When the user re-tags with new coords
  Then the existing photo_person row is updated (no duplicate)

  ### Link existing person without coords

  Given a processed photo with an open lightbox
  When the user dispatches link_existing_person for a person
  Then a photo_person row is created with nil coords

  ### Untag person

  Given an existing tag
  When the user dispatches untag
  Then the photo_person row is removed
  And an audit_log row is written for `Ancestry.Commands.UntagPersonFromPhoto`
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Galleries.PhotoPerson
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery, status: "processed")
    person = insert(:person, organization: org)

    Repo.insert!(%Ancestry.Organizations.AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })

    %{org: org, family: family, gallery: gallery, photo: photo, person: person}
  end

  test "tag → re-tag (upsert) → untag dispatches via Bus and writes audit rows",
       %{conn: conn, org: org, family: family, gallery: gallery, photo: photo, person: person} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()

    render_hook(view, "tag_person", %{
      "person_id" => to_string(person.id),
      "x" => 0.5,
      "y" => 0.4
    })

    assert [%PhotoPerson{x: 0.5, y: 0.4}] = Repo.all(PhotoPerson)

    render_hook(view, "tag_person", %{
      "person_id" => to_string(person.id),
      "x" => 0.7,
      "y" => 0.8
    })

    assert [%PhotoPerson{x: 0.7, y: 0.8}] = Repo.all(PhotoPerson)

    render_hook(view, "untag_person", %{
      "photo-id" => to_string(photo.id),
      "person-id" => to_string(person.id)
    })

    assert Repo.all(PhotoPerson) == []

    modules =
      Log
      |> Repo.all()
      |> Enum.map(& &1.command_module)
      |> Enum.sort()

    assert modules == [
             "Ancestry.Commands.TagPersonInPhoto",
             "Ancestry.Commands.TagPersonInPhoto",
             "Ancestry.Commands.UntagPersonFromPhoto"
           ]
  end

  test "link_existing_person tags without coords",
       %{conn: conn, org: org, family: family, gallery: gallery, photo: photo, person: person} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()

    render_hook(view, "link_existing_person", %{"person-id" => to_string(person.id)})

    assert [%PhotoPerson{x: nil, y: nil, person_id: pid}] = Repo.all(PhotoPerson)
    assert pid == person.id

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.TagPersonInPhoto"
  end
end
