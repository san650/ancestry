defmodule Web.PersonLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:search_mode, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> stream(:members, People.list_people_for_family(family_id))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
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
end
