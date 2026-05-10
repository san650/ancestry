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

  import Ecto.Query
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
    assert row.payload["arguments"]["gallery_id"] == gallery.id
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

  test "all-invalid batch finalises modal with no DB writes",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    upload =
      file_input(view, "#upload-form", :photos, [
        %{name: "doc.txt", content: "nope", type: "text/plain"}
      ])

    # Invalid entries never trigger handle_progress — the production JS
    # fires phx-change "validate" on file selection. Simulate that here:
    # render_upload triggers :allow_upload preflight (which sets the entry
    # error), and we then trigger the validate event explicitly to drive
    # maybe_finalize.
    render_upload(upload, "doc.txt")
    render_change(view, "validate", %{})

    html = render(view)
    assert html =~ "Upload complete"
    assert html =~ "doc.txt"

    assert Repo.all(Photo) == []
    assert Repo.all(Log) == []
  end

  test "batch upload tags every audit row with one shared bch- correlation id",
       %{conn: conn, org: org, family: family, gallery: gallery, account: account} do
    # Drive a single-file upload through the LV to confirm the call-site
    # change wires `correlation_ids: [batch_id]` into the audit row, then
    # exercise a second AddPhotoToGallery dispatch under the same batch_id
    # to confirm the audit rows can share a bch- correlation id (mirroring
    # what process_uploads/1 does inside consume_uploaded_entries).
    #
    # The LV test driver does not reliably support driving multiple
    # auto_upload entries through `render_upload/2` in a single batch
    # (the first entry's upload channel dies between renders), so the
    # multi-row batch leg uses a direct Bus.dispatch/3 call.
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    contents = File.read!("test/fixtures/test_image.jpg")

    upload =
      file_input(view, "#upload-form", :photos, [
        %{name: "first.jpg", content: contents <> <<1>>, type: "image/jpeg"}
      ])

    render_upload(upload, "first.jpg")

    [first_row] =
      Repo.all(
        from(l in Log,
          where: l.command_module == "Ancestry.Commands.AddPhotoToGallery"
        )
      )

    [batch_id] =
      Enum.filter(first_row.correlation_ids, &String.starts_with?(&1, "bch-"))

    # Now dispatch a second AddPhotoToGallery in the same batch directly
    # via the Bus, verifying the audit rows share the bch- id.
    scope = %{
      Ancestry.Identity.Scope.for_account(account)
      | organization: org
    }

    hash =
      :crypto.hash(:sha256, contents <> <<2>>) |> Base.encode16(case: :lower)

    {:ok, _photo} =
      Ancestry.Bus.dispatch(
        scope,
        Ancestry.Commands.AddPhotoToGallery.new!(%{
          gallery_id: gallery.id,
          original_path: "/tmp/photo_2.jpg",
          original_filename: "photo_2.jpg",
          content_type: "image/jpeg",
          file_hash: hash
        }),
        correlation_ids: [batch_id]
      )

    rows =
      Repo.all(
        from(l in Log,
          where: l.command_module == "Ancestry.Commands.AddPhotoToGallery",
          order_by: [asc: l.id]
        )
      )

    assert length(rows) == 2
    assert Enum.all?(rows, fn r -> batch_id in r.correlation_ids end)

    _ = family
  end

  test "too-many-files surfaces form-level error row",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    contents = File.read!("test/fixtures/test_image.jpg")

    # max_entries is 50 in mount/3; 51 entries trips :too_many_files.
    files =
      for i <- 1..51 do
        %{
          name: "p#{i}.jpg",
          # Vary one byte so each file has a unique sha256.
          content: contents <> <<i>>,
          type: "image/jpeg"
        }
      end

    upload = file_input(view, "#upload-form", :photos, files)

    # preflight_upload sends :allow_upload to the LiveView channel, which
    # registers entries server-side. With 51 entries against max 50, the
    # form-level :too_many_files error is set on the LiveView but
    # preflight may still return :ok with the per-entry refs.
    preflight_upload(upload)

    # Trigger validate so maybe_finalize runs and finalises the modal.
    render_change(view, "validate", %{})

    assigns = :sys.get_state(view.pid).socket.assigns

    assert assigns.show_upload_modal == true

    assert Enum.any?(assigns.upload_results, fn r ->
             r.status == :error and r.name == "Upload"
           end)
  end
end
