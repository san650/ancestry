defmodule Web.E2E.GalleryUploadTest do
  use Web.E2ECase

  alias Ancestry.Families
  alias Ancestry.Galleries

  # Allow extra time for LiveView processes to finish DB calls before the
  # sandbox owner shuts down.
  @moduletag ecto_sandbox_stop_owner_delay: 200

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})

    {:ok, gallery} =
      Galleries.create_gallery(%{name: "Upload Test Gallery", family_id: family.id})

    %{gallery: gallery, family: family, org: org}
  end

  test "upload button opens progress modal and adds photo to gallery", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    conn
    |> unwrap(fn %{frame_id: frame_id} ->
      PlaywrightEx.Frame.set_input_files(frame_id,
        selector: "#upload-form input[type=file]",
        local_paths: [Path.absname("test/fixtures/test_image.jpg")],
        timeout: 5_000
      )
    end)
    |> assert_has("#upload-modal", timeout: 5_000)
    |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]",
      timeout: 10_000
    )
  end

  test "drag and drop uploads photos", %{conn: conn, gallery: gallery, family: family, org: org} do
    conn = log_in_e2e(conn)

    conn
    |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
    |> wait_liveview()
    |> evaluate("""
      (function() {
        const dt = new DataTransfer();
        for (let i = 1; i <= 3; i++) {
          // Each file has unique bytes (trailing index byte) to avoid duplicate detection
          const minJpeg = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
            0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9, i]);
          dt.items.add(new File([minJpeg], `photo_${i}.jpg`, {type: 'image/jpeg'}));
        }
        document.body.dispatchEvent(
          new DragEvent('drop', {dataTransfer: dt, bubbles: true, cancelable: true})
        );
      })();
    """)
    |> assert_has("#upload-modal", timeout: 5_000)
    |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]",
      count: 3,
      timeout: 30_000
    )
  end

  # Dragging files over areas outside the gallery grid (e.g. the toolbar)
  # should still show the full-page drop overlay.
  test "dragging over the page header shows the full-page drop overlay", %{
    conn: conn,
    gallery: gallery,
    family: family,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn
    |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
    |> wait_liveview()
    |> evaluate("""
      const file = new File([''], 'photo.jpg', {type: 'image/jpeg'});
      const dt = new DataTransfer();
      dt.items.add(file);
      document.getElementById('toolbar').dispatchEvent(
        new DragEvent('dragenter', {dataTransfer: dt, bubbles: true, cancelable: true})
      );
    """)
    |> assert_has("#drag-overlay:not(.hidden)")
  end
end
