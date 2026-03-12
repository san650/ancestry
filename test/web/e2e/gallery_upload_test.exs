defmodule Web.E2E.GalleryUploadTest do
  use Web.E2ECase

  alias Family.Galleries

  # Allow extra time for LiveView processes to finish DB calls before the
  # sandbox owner shuts down.
  @moduletag ecto_sandbox_stop_owner_delay: 200

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Upload Test Gallery"})
    %{gallery: gallery}
  end

  # Bug 2: clicking the Upload button and selecting a file should open the
  # upload progress modal and add the photo to the gallery stream.
  # Uses Playwright's native set_input_files to closely mimic the real browser
  # file selection flow, rather than our JS-based upload_image helper which
  # bypasses the actual bug path.
  #
  test "upload button opens progress modal and adds photo to gallery", %{
    conn: conn,
    gallery: gallery
  } do
    conn =
      conn
      |> visit(~p"/galleries/#{gallery.id}")
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

  # Bug 1: dropping more than 10 files should upload all of them across
  # multiple batches. Currently only the first batch (10) is uploaded and
  # subsequent batches are not processed.
  #
  @tag :skip
  test "drag and drop uploads multiple batches of photos", %{
    conn: conn,
    gallery: gallery
  } do
    conn
    |> visit(~p"/galleries/#{gallery.id}")
    |> wait_liveview()
    |> evaluate("""
      (function() {
        const minJpeg = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
          0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9]);
        const dt = new DataTransfer();
        for (let i = 1; i <= 12; i++) {
          dt.items.add(new File([minJpeg], `photo_${i}.jpg`, {type: 'image/jpeg'}));
        }
        document.body.dispatchEvent(
          new DragEvent('drop', {dataTransfer: dt, bubbles: true, cancelable: true})
        );
      })();
    """)
    |> assert_has("#upload-modal", timeout: 5_000)
    |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]",
      count: 12,
      timeout: 30_000
    )
  end

  # Dragging files over areas outside the gallery grid (e.g. the toolbar)
  # should still show the full-page drop overlay.
  test "dragging over the page header shows the full-page drop overlay", %{
    conn: conn,
    gallery: gallery
  } do
    conn
    |> visit(~p"/galleries/#{gallery.id}")
    |> wait_liveview()
    |> evaluate("""
      const file = new File([''], 'photo.jpg', {type: 'image/jpeg'});
      const dt = new DataTransfer();
      dt.items.add(file);
      document.getElementById('upload-btn').dispatchEvent(
        new DragEvent('dragenter', {dataTransfer: dt, bubbles: true, cancelable: true})
      );
    """)
    |> assert_has("#drag-overlay:not(.hidden)")
  end
end
