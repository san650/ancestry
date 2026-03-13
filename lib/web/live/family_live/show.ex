defmodule Web.FamilyLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "family:#{family_id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:editing, false)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(Families.change_family(family)))
     |> assign(:show_new_gallery_modal, false)
     |> assign(:confirm_delete_gallery, nil)
     |> assign(:gallery_form, to_form(Galleries.change_gallery(%Gallery{})))
     |> assign(:search_mode, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> stream(:galleries, Galleries.list_galleries(family_id))
     |> stream(:members, People.list_people_for_family(family_id))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit", _, socket) do
    form = to_form(Families.change_family(socket.assigns.family))
    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("validate", %{"family" => params}, socket) do
    changeset =
      socket.assigns.family
      |> Families.change_family(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"family" => params}, socket) do
    case Families.update_family(socket.assigns.family, params) do
      {:ok, family} ->
        {:noreply,
         socket
         |> assign(:family, family)
         |> assign(:editing, false)
         |> assign(:form, to_form(Families.change_family(family)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Families.delete_family(socket.assigns.family)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # Gallery management

  def handle_event("open_new_gallery_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_gallery_modal, true)
     |> assign(:gallery_form, to_form(Galleries.change_gallery(%Gallery{})))}
  end

  def handle_event("close_new_gallery_modal", _, socket) do
    {:noreply, assign(socket, :show_new_gallery_modal, false)}
  end

  def handle_event("validate_gallery", %{"gallery" => params}, socket) do
    changeset =
      %Gallery{}
      |> Galleries.change_gallery(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :gallery_form, to_form(changeset))}
  end

  def handle_event("save_gallery", %{"gallery" => params}, socket) do
    params = Map.put(params, "family_id", socket.assigns.family.id)

    case Galleries.create_gallery(params) do
      {:ok, gallery} ->
        {:noreply,
         socket
         |> assign(:show_new_gallery_modal, false)
         |> stream_insert(:galleries, gallery)}

      {:error, changeset} ->
        {:noreply, assign(socket, :gallery_form, to_form(changeset))}
    end
  end

  def handle_event("request_delete_gallery", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, Galleries.get_gallery!(id))}
  end

  def handle_event("cancel_delete_gallery", _, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, nil)}
  end

  def handle_event("confirm_delete_gallery", _, socket) do
    gallery = socket.assigns.confirm_delete_gallery
    {:ok, _} = Galleries.delete_gallery(gallery)

    {:noreply,
     socket
     |> assign(:confirm_delete_gallery, nil)
     |> stream_delete(:galleries, gallery)}
  end

  # Member search/link

  def handle_event("open_search", _, socket) do
    {:noreply, assign(socket, :search_mode, true)}
  end

  def handle_event("close_search", _, socket) do
    {:noreply,
     socket
     |> assign(:search_mode, false)
     |> assign(:search_results, [])
     |> assign(:search_query, "")}
  end

  def handle_event("search", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2 do
        People.search_people(query, socket.assigns.family.id)
      else
        []
      end

    {:noreply, socket |> assign(:search_query, query) |> assign(:search_results, results)}
  end

  def handle_event("link_person", %{"id" => id}, socket) do
    person = People.get_person!(String.to_integer(id))
    family = socket.assigns.family

    case People.add_to_family(person, family) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_insert(:members, person)
         |> assign(:search_mode, false)
         |> assign(:search_results, [])
         |> assign(:search_query, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cover_processed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end

  def handle_info({:cover_failed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end

  defp format_partial_date(day, month, year) do
    [day, month, year]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      parts -> Enum.join(parts, "/")
    end
  end
end
