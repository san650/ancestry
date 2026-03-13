defmodule Web.PersonLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  @impl true
  def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
    family = Families.get_family!(family_id)
    person = People.get_person!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, person)
     |> assign(:editing, false)
     |> assign(:confirm_remove, false)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(People.change_person(person)))
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit", _, socket) do
    form = to_form(People.change_person(socket.assigns.person))
    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params = process_alternate_names(params)

    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:editing, false)
         |> assign(:form, to_form(People.change_person(person)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    family = socket.assigns.family
    person = socket.assigns.person
    {:ok, _} = People.remove_from_family(person, family)
    {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}")}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    family = socket.assigns.family
    {:ok, _} = People.delete_person(socket.assigns.person)
    {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}")}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  @impl true
  def handle_info({:person_photo_processed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:person_photo_failed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} ->
        params

      {"", params} ->
        params

      {text, params} ->
        names =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "alternate_names", names)
    end
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

  defp format_partial_date(day, month, year) do
    [day, month, year]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      parts -> Enum.join(parts, "/")
    end
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
