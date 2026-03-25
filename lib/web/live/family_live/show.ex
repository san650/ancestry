defmodule Web.FamilyLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Families.Metrics
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery
  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.People.PersonTree

  import Web.FamilyLive.PersonCardComponent

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "family:#{family_id}")
    end

    people = People.list_people_for_family(family_id)
    galleries = Galleries.list_galleries(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:galleries, galleries)
     |> assign_async(:metrics, fn -> {:ok, %{metrics: Metrics.compute(family_id)}} end,
       supervisor: Ancestry.TaskSupervisor
     )
     |> assign(:tree, nil)
     |> assign(:focus_person, nil)
     |> assign(:editing, false)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(Families.change_family(family)))
     |> assign(:show_new_gallery_modal, false)
     |> assign(:confirm_delete_gallery, nil)
     |> assign(:gallery_form, to_form(Galleries.change_gallery(%Gallery{})))
     |> assign(:search_mode, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:adding_relationship, nil)
     |> assign(:default_person_id, get_default_person_id(family_id))
     |> assign(:default_person_filter, "")
     |> assign(:show_create_subfamily_modal, false)
     |> assign(:subfamily_person, nil)
     |> assign(:subfamily_form, to_form(Families.change_family(%Ancestry.Families.Family{})))
     |> assign(:subfamily_include_ancestors, true)
     |> assign(:subfamily_include_partner_ancestors, false)}
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
          # Fallback to default person
          case People.get_default_person(socket.assigns.family.id) do
            nil -> nil
            default -> Enum.find(people, &(&1.id == default.id))
          end
      end

    tree =
      if focus_person do
        PersonTree.build(focus_person, socket.assigns.family.id)
      else
        nil
      end

    socket =
      socket
      |> assign(:focus_person, focus_person)
      |> assign(:tree, tree)

    socket = if focus_person, do: push_event(socket, "scroll_to_focus", %{}), else: socket

    {:noreply, socket}
  end

  # Focus person event — re-center tree

  @impl true
  def handle_event("focus_person", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}?person=#{id}"
     )}
  end

  # Family editing

  def handle_event("edit", _, socket) do
    form = to_form(Families.change_family(socket.assigns.family))

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:form, form)
     |> assign(:default_person_id, get_default_person_id(socket.assigns.family.id))
     |> assign(:default_person_filter, "")}
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
        # Persist default person selection
        case socket.assigns.default_person_id do
          nil -> People.clear_default_member(family.id)
          person_id -> People.set_default_member(family.id, person_id)
        end

        # Update tree view to reflect new default person
        {focus_person, tree} =
          case socket.assigns.default_person_id do
            nil ->
              {nil, nil}

            person_id ->
              person = Enum.find(socket.assigns.people, &(&1.id == person_id))
              tree = if person, do: PersonTree.build(person, family.id), else: nil
              {person, tree}
          end

        {:noreply,
         socket
         |> assign(:family, family)
         |> assign(:editing, false)
         |> assign(:form, to_form(Families.change_family(family)))
         |> assign(:focus_person, focus_person)
         |> assign(:tree, tree)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("filter_default_person", %{"value" => query}, socket) do
    {:noreply, assign(socket, :default_person_filter, query)}
  end

  def handle_event("select_default_person", %{"id" => id}, socket) do
    {:noreply, assign(socket, :default_person_id, String.to_integer(id))}
  end

  def handle_event("clear_default_person", _, socket) do
    {:noreply, assign(socket, :default_person_id, nil)}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Families.delete_family(socket.assigns.family)

    {:noreply,
     push_navigate(socket, to: ~p"/org/#{socket.assigns.current_scope.organization.id}")}
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
      {:ok, _gallery} ->
        galleries = Galleries.list_galleries(socket.assigns.family.id)
        metrics = Metrics.compute(socket.assigns.family.id)

        {:noreply,
         socket
         |> assign(:show_new_gallery_modal, false)
         |> assign(:galleries, galleries)
         |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))}

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
    galleries = Galleries.list_galleries(socket.assigns.family.id)
    metrics = Metrics.compute(socket.assigns.family.id)

    {:noreply,
     socket
     |> assign(:confirm_delete_gallery, nil)
     |> assign(:galleries, galleries)
     |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))}
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
        People.search_people(
          query,
          socket.assigns.family.id,
          socket.assigns.current_scope.organization.id
        )
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
        people = People.list_people_for_family(family.id)
        metrics = Metrics.compute(family.id)

        focus_person = socket.assigns.focus_person
        tree = if focus_person, do: PersonTree.build(focus_person, family.id), else: nil

        {:noreply,
         socket
         |> assign(:people, people)
         |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))
         |> assign(:tree, tree)
         |> assign(:search_mode, false)
         |> assign(:search_results, [])
         |> assign(:search_query, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Add relationship from tree placeholders

  def handle_event("add_relationship", %{"type" => type, "person-id" => person_id}, socket) do
    {:noreply,
     assign(socket, :adding_relationship, %{
       type: to_string(type),
       person_id: String.to_integer(person_id)
     })}
  end

  def handle_event("cancel_add_relationship", _, socket) do
    {:noreply, assign(socket, :adding_relationship, nil)}
  end

  # Create subfamily modal

  def handle_event("open_create_subfamily", _, socket) do
    person = socket.assigns.focus_person || hd(socket.assigns.people)
    name = person.surname || ""

    {:noreply,
     socket
     |> assign(:show_create_subfamily_modal, true)
     |> assign(:subfamily_person, person)
     |> assign(
       :subfamily_form,
       to_form(Families.change_family(%Ancestry.Families.Family{}, %{name: name}))
     )
     |> assign(:subfamily_include_ancestors, true)
     |> assign(:subfamily_include_partner_ancestors, false)}
  end

  def handle_event("close_create_subfamily", _, socket) do
    {:noreply,
     socket
     |> assign(:show_create_subfamily_modal, false)
     |> assign(:subfamily_person, nil)}
  end

  def handle_event("validate_subfamily", %{"family" => params}, socket) do
    changeset =
      %Ancestry.Families.Family{}
      |> Families.change_family(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :subfamily_form, to_form(changeset))}
  end

  def handle_event("toggle_ancestors", params, socket) do
    {:noreply, assign(socket, :subfamily_include_ancestors, params["value"] == "true")}
  end

  def handle_event("toggle_partner_ancestors", params, socket) do
    {:noreply, assign(socket, :subfamily_include_partner_ancestors, params["value"] == "true")}
  end

  def handle_event("save_subfamily", %{"family" => params}, socket) do
    person = socket.assigns.subfamily_person
    family = socket.assigns.family
    org = socket.assigns.current_scope.organization

    case Families.create_family_from_person(org, params["name"], person, family.id,
           include_ancestors: socket.assigns.subfamily_include_ancestors,
           include_partner_ancestors: socket.assigns.subfamily_include_partner_ancestors
         ) do
      {:ok, new_family} ->
        {:noreply,
         socket
         |> assign(:show_create_subfamily_modal, false)
         |> push_navigate(to: ~p"/org/#{org.id}/families/#{new_family.id}?person=#{person.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :subfamily_form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create subfamily")
         |> assign(:show_create_subfamily_modal, false)}
    end
  end

  # PubSub

  def handle_info({:subfamily_person_selected, person_id}, socket) do
    person = find_person(socket.assigns.people, person_id)
    name = person.surname || ""

    {:noreply,
     socket
     |> assign(:subfamily_person, person)
     |> assign(
       :subfamily_form,
       to_form(Families.change_family(%Ancestry.Families.Family{}, %{name: name}))
     )}
  end

  @impl true
  def handle_info({:cover_processed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end

  def handle_info({:cover_failed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end

  def handle_info({:focus_person, person_id}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}?person=#{person_id}"
     )}
  end

  def handle_info({:relationship_saved, _type, _person}, socket) do
    family = socket.assigns.family
    people = People.list_people_for_family(family.id)
    metrics = Metrics.compute(family.id)
    focus_person = socket.assigns.focus_person

    focus_person =
      if focus_person do
        Enum.find(people, &(&1.id == focus_person.id))
      end

    tree =
      if focus_person do
        PersonTree.build(focus_person, family.id)
      end

    {:noreply,
     socket
     |> assign(:people, people)
     |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))
     |> assign(:focus_person, focus_person)
     |> assign(:tree, tree)
     |> assign(:adding_relationship, nil)
     |> put_flash(:info, "Relationship added")}
  end

  def handle_info({:relationship_error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # assign_async spawns linked tasks that send :EXIT on completion
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  # Private helpers

  defp count_parents(nil), do: 0

  defp count_parents(%{couple: %{person_a: a, person_b: b}}) do
    count = if a, do: 1, else: 0
    count + if(b, do: 1, else: 0)
  end

  defp find_person(people, person_id) do
    Enum.find(people, &(&1.id == person_id)) || People.get_person!(person_id)
  end

  defp get_default_person_id(family_id) do
    case People.get_default_person(family_id) do
      nil -> nil
      person -> person.id
    end
  end

  defp filtered_people(people, filter) do
    if String.trim(filter) == "" do
      people
    else
      filter = Ancestry.StringUtils.normalize(filter)

      Enum.filter(people, fn person ->
        name = Person.display_name(person) |> Ancestry.StringUtils.normalize()
        String.contains?(name, filter)
      end)
    end
  end
end
