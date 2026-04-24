defmodule Web.FamilyLive.Print do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.PersonGraph
  alias Ancestry.Relationships

  import Web.FamilyLive.PrintGraphComponent

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    people = People.list_people_for_family(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    family_graph = FamilyGraph.from(people, relationships, family.id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:family_graph, family_graph)
     |> assign(:page_title, family.name)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    people = socket.assigns.people

    focus_person =
      case params do
        %{"person" => id} ->
          person_id = String.to_integer(id)
          Enum.find(people, &(&1.id == person_id))

        _ ->
          case People.get_default_person(socket.assigns.family.id) do
            nil -> List.first(people)
            default -> Enum.find(people, &(&1.id == default.id))
          end
      end

    tree_ancestors = parse_depth(params, "ancestors", 2)
    tree_descendants = parse_depth(params, "descendants", 2)
    tree_other = parse_depth(params, "other", 1)

    {tree_ancestors, tree_descendants, tree_other} =
      if params["display"] == "complete" do
        {20, 20, 20}
      else
        {tree_ancestors, tree_descendants, min(tree_other, tree_ancestors)}
      end

    graph =
      if focus_person do
        PersonGraph.build(focus_person, socket.assigns.family_graph,
          ancestors: tree_ancestors,
          descendants: tree_descendants,
          other: tree_other
        )
      end

    {:noreply, assign(socket, :graph, graph)}
  end

  defp parse_depth(params, key, default) do
    case Integer.parse(params[key] || "") do
      {n, _} when n >= 1 and n <= 20 -> n
      _ -> default
    end
  end
end
