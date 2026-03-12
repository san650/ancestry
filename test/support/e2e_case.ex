defmodule Web.E2ECase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use PhoenixTest.Playwright.Case, async: true
      use Web, :verified_routes
      @moduletag :e2e
      import Web.E2ECase
    end
  end

  def wait_liveview(conn) do
    PhoenixTest.assert_has(conn, "body .phx-connected")
  end

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

  defp mime_for_extension(".jpg"), do: "image/jpeg"
  defp mime_for_extension(".jpeg"), do: "image/jpeg"
  defp mime_for_extension(".png"), do: "image/png"
  defp mime_for_extension(".webp"), do: "image/webp"
  defp mime_for_extension(".gif"), do: "image/gif"
  defp mime_for_extension(_), do: "application/octet-stream"
end
