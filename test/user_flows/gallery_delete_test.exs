defmodule Web.UserFlows.GalleryDeleteTest do
  @moduledoc """
  Verifies that deleting a gallery via the family-show LiveView dispatches
  `RemoveGalleryFromFamily` through the Bus, cascades photos / photo_people /
  photo_comments, and writes an audit row.

  ## Scenario

  ### Bus-driven gallery deletion + cascade

  Given an admin viewing the family-show page for a family with one gallery
  And the gallery has a photo with a tagged person and a comment
  When the user requests delete and confirms
  Then the gallery is removed
  And the photo, photo_person and photo_comment cascade-delete
  And an audit_log row is written for `Ancestry.Commands.RemoveGalleryFromFamily`
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Galleries.{Gallery, Photo, PhotoPerson}
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    person = insert(:person, organization: org)
    photo_comment = insert(:photo_comment, photo: photo)

    photo_person =
      Repo.insert!(%PhotoPerson{photo_id: photo.id, person_id: person.id, x: 0.5, y: 0.5})

    Repo.insert!(%Ancestry.Organizations.AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })

    %{
      org: org,
      family: family,
      gallery: gallery,
      photo: photo,
      photo_person: photo_person,
      photo_comment: photo_comment
    }
  end

  test "deletes a gallery via the bus and cascades dependents",
       %{
         conn: conn,
         org: org,
         family: family,
         gallery: gallery,
         photo: photo,
         photo_person: photo_person,
         photo_comment: photo_comment
       } do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")

    render_click(view, "request_delete_gallery", %{"id" => to_string(gallery.id)})
    assert has_element?(view, "#confirm-delete-gallery-modal")

    render_click(view, "confirm_delete_gallery", %{})

    refute has_element?(view, "#confirm-delete-gallery-modal")
    refute has_element?(view, "#side-panel-gallery-list-#{gallery.id}")

    refute Repo.get(Gallery, gallery.id)
    refute Repo.get(Photo, photo.id)
    refute Repo.get(PhotoPerson, photo_person.id)
    refute Repo.get(PhotoComment, photo_comment.id)

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.RemoveGalleryFromFamily"
    assert row.payload["gallery_id"] == gallery.id
  end
end
