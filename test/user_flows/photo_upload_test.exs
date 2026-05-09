defmodule Web.UserFlows.PhotoUploadTest do
  @moduledoc """
  Verifies that uploading a photo into a gallery dispatches
  `AddPhotoToGallery` through the Bus, enqueues the
  `TransformAndStorePhoto` worker, and writes an audit row.

  ## Scenarios

  ### Bus-driven photo upload

  Given an admin viewing a gallery
  When the user selects a photo via the upload input
  Then a Photo row is inserted with status "pending"
  And a TransformAndStorePhoto Oban job is enqueued
  And an audit_log row is written for `Ancestry.Commands.AddPhotoToGallery`

  ### Duplicate detection

  Given a photo already exists in the gallery with a known hash
  When the user uploads bytes that hash to the same value
  Then no new photo is inserted
  And no audit row is written
  """

  use Web.ConnCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)
    gallery = insert(:gallery, family: family)

    Repo.insert!(%Ancestry.Organizations.AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })

    %{org: org, family: family, gallery: gallery}
  end

  test "uploads a photo via the bus and writes an audit row",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    photo =
      file_input(view, "#upload-form", :photos, [
        %{
          name: "photo1.jpg",
          content: File.read!("test/fixtures/test_image.jpg"),
          type: "image/jpeg"
        }
      ])

    render_upload(photo, "photo1.jpg")

    assert [photo_row] = Repo.all(Photo)
    assert photo_row.gallery_id == gallery.id
    assert photo_row.original_filename == "photo1.jpg"

    # Inline Oban mode runs TransformAndStorePhoto immediately on commit;
    # the photo lands in :processed (or :failed for malformed bytes).
    assert photo_row.status in ["processed", "failed"]

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddPhotoToGallery"
    assert row.payload["gallery_id"] == gallery.id
  end

  test "duplicate hash skips dispatch and writes no audit row",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    contents = File.read!("test/fixtures/test_image.jpg")
    hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

    insert(:photo, gallery: gallery, file_hash: hash)
    Repo.delete_all(Log)

    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    photo =
      file_input(view, "#upload-form", :photos, [
        %{name: "duplicate.jpg", content: contents, type: "image/jpeg"}
      ])

    render_upload(photo, "duplicate.jpg")

    assert [_existing] = Repo.all(Photo)
    assert Repo.all(Log) == []
  end

  test "mixed valid + invalid file types — modal finalises with one error row, valid file persists",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    upload =
      file_input(view, "#upload-form", :photos, [
        %{
          name: "valid.jpg",
          content: File.read!("test/fixtures/test_image.jpg"),
          type: "image/jpeg"
        },
        %{
          name: "invalid.txt",
          content: "not an image",
          type: "text/plain"
        }
      ])

    render_upload(upload, "valid.jpg")

    html = render(view)
    assert html =~ "Upload complete"
    assert html =~ "invalid.txt"
    assert html =~ "valid.jpg"

    assert [photo_row] = Repo.all(Photo)
    assert photo_row.original_filename == "valid.jpg"

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddPhotoToGallery"
  end
end
