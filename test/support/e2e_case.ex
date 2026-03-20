defmodule Web.E2ECase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use PhoenixTest.Playwright.Case, async: true
      use Web, :verified_routes
      @moduletag :e2e
      import Web.E2ECase
      import Ancestry.Factory
    end
  end

  @doc """
  Returns a CSS attribute selector for `data-testid`.

      click(conn, test_id("family-new-btn"))
      assert_has(conn, test_id("family-name"), text: "The Smiths")
  """
  def test_id(id), do: "[data-testid='#{id}']"

  @doc """
  Simulates selecting files via a file input element.

  Reads each file from disk, encodes the binary content, and injects it into
  the browser as `File` objects on the element matching `selector`, then
  dispatches a `change` event so LiveView's auto-upload picks them up.
  """
  def upload_image(conn, selector, file_paths) when is_list(file_paths) do
    files_json =
      file_paths
      |> Enum.map(fn path ->
        %{
          name: Path.basename(path),
          mime: mime_for_extension(Path.extname(path)),
          data: path |> File.read!() |> Base.encode64()
        }
      end)
      |> Jason.encode!()

    PhoenixTest.Playwright.evaluate(conn, """
      (function() {
        const files = #{files_json};
        const dt = new DataTransfer();
        files.forEach(({name, mime, data}) => {
          const bytes = Uint8Array.from(atob(data), c => c.charCodeAt(0));
          dt.items.add(new File([bytes], name, {type: mime}));
        });
        const input = document.querySelector(#{Jason.encode!(selector)});
        input.files = dt.files;
        input.dispatchEvent(new Event('change', {bubbles: true}));
      })();
    """)
  end

  @doc """
  Creates placeholder image files for a factory-created photo so the browser
  can fetch them without 404 errors during E2E tests.

  Waffle's Photo uploader appends `.jpg` to transformed version filenames
  (e.g. `thumbnail.jpg` + `:jpg` transform → `thumbnail.jpg.jpg`).
  """
  def ensure_photo_file(%Ancestry.Galleries.Photo{} = photo) do
    photo = Ancestry.Repo.preload(photo, :gallery)

    dir =
      Path.join([
        "tmp/test_uploads/uploads/photos",
        "#{photo.gallery.family_id}",
        "#{photo.gallery_id}",
        "#{photo.id}"
      ])

    File.mkdir_p!(dir)
    source = "test/fixtures/test_image.jpg"
    File.cp!(source, Path.join(dir, "thumbnail.jpg.jpg"))
    File.cp!(source, Path.join(dir, "large.jpg.jpg"))
    File.cp!(source, Path.join(dir, "original#{Path.extname(photo.original_filename)}"))
    photo
  end

  defp mime_for_extension(".jpg"), do: "image/jpeg"
  defp mime_for_extension(".jpeg"), do: "image/jpeg"
  defp mime_for_extension(".png"), do: "image/png"
  defp mime_for_extension(".webp"), do: "image/webp"
  defp mime_for_extension(".gif"), do: "image/gif"
  defp mime_for_extension(_), do: "application/octet-stream"

  def wait_liveview(conn, async_containers \\ []) do
    async_containers = [
      "body .phx-connected"
      | async_containers
    ]

    Enum.reduce(async_containers, conn, &PhoenixTest.assert_has(&2, &1))
  end
end
