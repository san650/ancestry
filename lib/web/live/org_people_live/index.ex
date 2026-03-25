defmodule Web.OrgPeopleLive.Index do
  use Web, :live_view

  alias Ancestry.People

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    people = People.list_people_for_org(org.id)

    {:ok,
     socket
     |> assign(:filter, "")
     |> assign(:editing, false)
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_delete, false)
     |> assign(:no_family_only, false)
     |> assign(:people_empty?, people == [])
     |> stream_configure(:people, dom_id: fn {person, _rel_count} -> "people-#{person.id}" end)
     |> stream(:people, people)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"filter" => query}, socket) do
    org_id = socket.assigns.current_scope.organization.id

    people =
      People.list_people_for_org(org_id, query, no_family_only: socket.assigns.no_family_only)

    {:noreply,
     socket
     |> assign(:filter, query)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_edit", _, socket) do
    editing = !socket.assigns.editing
    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:editing, editing)
     |> assign(:selected, MapSet.new())
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_no_family", _, socket) do
    no_family_only = !socket.assigns.no_family_only
    people = refetch_people(socket, no_family_only: no_family_only)

    {:noreply,
     socket
     |> assign(:no_family_only, no_family_only)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    person_id = String.to_integer(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, person_id) do
        MapSet.delete(selected, person_id)
      else
        MapSet.put(selected, person_id)
      end

    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> stream(:people, people, reset: true)}
  end

  def handle_event("select_all", _, socket) do
    people = refetch_people(socket)
    ids = MapSet.new(people, fn {p, _} -> p.id end)

    {:noreply,
     socket
     |> assign(:selected, ids)
     |> stream(:people, people, reset: true)}
  end

  def handle_event("deselect_all", _, socket) do
    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> stream(:people, people, reset: true)}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("request_delete_one", %{"id" => id}, socket) do
    if socket.assigns.confirm_delete do
      {:noreply, socket}
    else
      person_id = String.to_integer(id)

      {:noreply,
       socket
       |> assign(:selected, MapSet.new([person_id]))
       |> assign(:confirm_delete, true)}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    selected = socket.assigns.selected
    count = MapSet.size(selected)

    People.delete_people(MapSet.to_list(selected))

    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_delete, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)
     |> put_flash(
       :info,
       "Deleted #{count} #{if count == 1, do: "person", else: "people"}."
     )}
  end

  defp refetch_people(socket, opts \\ []) do
    no_family_only = Keyword.get(opts, :no_family_only, socket.assigns.no_family_only)

    People.list_people_for_org(
      socket.assigns.current_scope.organization.id,
      socket.assigns.filter,
      no_family_only: no_family_only
    )
  end

  def estimated_age(%{birth_year: nil}), do: nil

  def estimated_age(%{deceased: true, death_year: nil}), do: nil

  def estimated_age(%{deceased: true, birth_year: birth_year, death_year: death_year}),
    do: death_year - birth_year

  def estimated_age(%{birth_year: birth_year}),
    do: Date.utc_today().year - birth_year
end
