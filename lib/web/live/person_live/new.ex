defmodule Web.PersonLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, %Person{})
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:person_saved, person}, socket) do
    socket = maybe_process_photo(socket, person)
    {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}
  end

  def handle_info({:cancel_upload, ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end
end
