defmodule Web.PersonLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, %Person{})
     |> assign(:form, to_form(People.change_person(%Person{})))
     |> assign(:show_details, false)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_details", _, socket) do
    {:noreply, assign(socket, :show_details, true)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    params = invert_living_to_deceased(params)

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params =
      params
      |> invert_living_to_deceased()
      |> process_alternate_names()

    case People.create_person(socket.assigns.family, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         push_navigate(socket,
           to:
             ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}"
     )}
  end

  # --- Private helpers ---

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
        original_path = Ancestry.Storage.store_original(tmp_path, dest_key)
        {:ok, original_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end

  defp invert_living_to_deceased(params) do
    case Map.pop(params, "living") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "deceased", "false")
      {"false", params} -> Map.put(params, "deceased", "true")
      {_, params} -> params
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} ->
        params

      {"", params} ->
        params

      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end
end
