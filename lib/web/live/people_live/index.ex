defmodule Web.PeopleLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    people = People.list_people_for_family_with_relationship_counts(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:filter, "")
     |> assign(:editing, false)
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_remove, false)
     |> assign(:unlinked_only, false)
     |> assign(:people_empty?, people == [])
     |> stream_configure(:people, dom_id: fn {person, _rel_count} -> "people-#{person.id}" end)
     |> stream(:people, people)}
  end

  @impl true
  def handle_event("filter", %{"filter" => query}, socket) do
    family_id = socket.assigns.family.id

    people =
      People.list_people_for_family_with_relationship_counts(family_id, query,
        unlinked_only: socket.assigns.unlinked_only
      )

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

  def handle_event("toggle_unlinked", _, socket) do
    unlinked_only = !socket.assigns.unlinked_only
    people = refetch_people(socket, unlinked_only: unlinked_only)

    {:noreply,
     socket
     |> assign(:unlinked_only, unlinked_only)
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

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("request_remove_one", %{"id" => id}, socket) do
    if socket.assigns.confirm_remove do
      {:noreply, socket}
    else
      person_id = String.to_integer(id)

      {:noreply,
       socket
       |> assign(:selected, MapSet.new([person_id]))
       |> assign(:confirm_remove, true)}
    end
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    family = socket.assigns.family
    selected = socket.assigns.selected
    count = MapSet.size(selected)

    for person_id <- selected do
      person = People.get_person!(person_id)
      People.remove_from_family(person, family)
    end

    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_remove, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)
     |> put_flash(
       :info,
       "Removed #{count} #{if count == 1, do: "person", else: "people"} from the family."
     )}
  end

  defp refetch_people(socket, opts \\ []) do
    unlinked_only = Keyword.get(opts, :unlinked_only, socket.assigns.unlinked_only)

    People.list_people_for_family_with_relationship_counts(
      socket.assigns.family.id,
      socket.assigns.filter,
      unlinked_only: unlinked_only
    )
  end

  def estimated_age(%{birth_year: nil}), do: nil

  def estimated_age(%{deceased: true, death_year: nil}), do: nil

  def estimated_age(%{deceased: true, birth_year: birth_year, death_year: death_year}),
    do: death_year - birth_year

  def estimated_age(%{birth_year: birth_year}),
    do: Date.utc_today().year - birth_year
end
