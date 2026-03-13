defmodule Web.FamilyLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Families.Family

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(Families.change_family(%Family{})))
     |> allow_upload(:cover,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"family" => params}, socket) do
    changeset =
      %Family{}
      |> Families.change_family(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"family" => params}, socket) do
    case Families.create_family(params) do
      {:ok, family} ->
        socket =
          maybe_process_cover(socket, family)

        {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}/galleries")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :cover, ref)}
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp maybe_process_cover(socket, family) do
    uploaded =
      consume_uploaded_entries(socket, :cover, fn %{path: tmp_path}, _entry ->
        uuid = Ecto.UUID.generate()
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "cover#{Path.extname(tmp_path)}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        Families.update_cover_pending(family, original_path)
        socket

      [] ->
        socket
    end
  end
end
