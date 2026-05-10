defmodule Web.UserFlows.PhotoDeleteTest do
  @moduledoc """
  Verifies that deleting a photo from a gallery dispatches
  `RemovePhotoFromGallery` through the Bus, writes an audit row,
  and removes the photo from the gallery stream.

  ## Scenario

  ### Bus-driven photo deletion + audit row

  Given an admin viewing a gallery containing one processed photo
  When the user enters selection mode, selects the photo, requests delete and confirms
  Then the photo is removed from the DB
  And the photo no longer appears in the grid
  And an audit_log row is written for `Ancestry.Commands.RemovePhotoFromGallery`
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery, status: "processed")

    Repo.insert!(%Ancestry.Organizations.AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })

    %{org: org, family: family, gallery: gallery, photo: photo}
  end

  test "deletes a photo via the bus and writes an audit row",
       %{conn: conn, org: org, family: family, gallery: gallery, photo: photo} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    render_click(view, "toggle_select_mode", %{})
    render_click(view, "toggle_photo_select", %{"id" => to_string(photo.id)})
    render_click(view, "request_delete_photos", %{})
    render_click(view, "confirm_delete_photos", %{})

    refute Repo.get(Photo, photo.id)
    refute has_element?(view, "#photos-#{photo.id}")

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.RemovePhotoFromGallery"
    assert row.payload["arguments"]["photo_id"] == photo.id
  end
end
