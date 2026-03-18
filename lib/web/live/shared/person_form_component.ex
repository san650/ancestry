defmodule Web.Shared.PersonFormComponent do
  use Web, :live_component

  alias Ancestry.People

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(assigns, socket) do
    person = assigns.person
    changeset = People.change_person(person)

    extra_fields_present? =
      birth_name_differs?(person.given_name_at_birth, person.given_name) ||
        birth_name_differs?(person.surname_at_birth, person.surname) ||
        has_value?(person.nickname) ||
        has_value?(person.title) ||
        has_value?(person.suffix) ||
        (person.alternate_names != nil and person.alternate_names != [])

    show_details = socket.assigns[:show_details] || extra_fields_present?

    {:ok,
     socket
     |> assign(:person, person)
     |> assign(:family, assigns.family)
     |> assign(:action, assigns.action)
     |> assign(:parent_uploads, assigns.uploads)
     |> assign(:form, to_form(changeset))
     |> assign(:show_details, show_details)}
  end

  # -------------------------------------------------------------------
  # Event handlers
  # -------------------------------------------------------------------

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

    case socket.assigns.action do
      :new ->
        case People.create_person(socket.assigns.family, params) do
          {:ok, person} ->
            send(self(), {:person_saved, person})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end

      :edit ->
        case People.update_person(socket.assigns.person, params) do
          {:ok, person} ->
            send(self(), {:person_saved, person})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    send(self(), {:cancel_upload, ref})
    {:noreply, socket}
  end

  def handle_event("cancel", _, socket) do
    case socket.assigns.action do
      :new ->
        {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}

      :edit ->
        send(self(), {:cancel_edit})
        {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(_), do: true

  defp birth_name_differs?(nil, _current), do: false
  defp birth_name_differs?("", _current), do: false
  defp birth_name_differs?(birth, current), do: birth != current

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

  defp living_checked?(form) do
    val = form[:deceased].value
    !(val in ["true", true])
  end

  defp month_options do
    [
      {"Jan", "1"},
      {"Feb", "2"},
      {"Mar", "3"},
      {"Apr", "4"},
      {"May", "5"},
      {"Jun", "6"},
      {"Jul", "7"},
      {"Aug", "8"},
      {"Sep", "9"},
      {"Oct", "10"},
      {"Nov", "11"},
      {"Dec", "12"}
    ]
  end

  defp day_options do
    Enum.map(1..31, fn d -> {to_string(d), to_string(d)} end)
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
