defmodule Web.PeopleLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)
    people = People.list_people_for_family_with_relationship_counts(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:filter, "")
     |> assign(:editing, false)
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_remove, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people)}
  end

  @impl true
  def handle_event("filter", %{"filter" => query}, socket) do
    family_id = socket.assigns.family.id
    people = People.list_people_for_family_with_relationship_counts(family_id, query)

    {:noreply,
     socket
     |> assign(:filter, query)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_edit", _, socket) do
    editing = !socket.assigns.editing

    {:noreply,
     socket
     |> assign(:editing, editing)
     |> assign(:selected, MapSet.new())}
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

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _, socket) do
    family_id = socket.assigns.family.id
    filter = socket.assigns.filter
    people = People.list_people_for_family_with_relationship_counts(family_id, filter)
    ids = MapSet.new(people, fn {p, _} -> p.id end)

    {:noreply, assign(socket, :selected, ids)}
  end

  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
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

    people =
      People.list_people_for_family_with_relationship_counts(family.id, socket.assigns.filter)

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
end
