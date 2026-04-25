defmodule Web.FamilyLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Families.Metrics
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Memories
  alias Ancestry.Memories.Vault
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person
  alias Ancestry.People.PersonGraph
  alias Ancestry.People.PersonTree
  alias Ancestry.Relationships

  import Web.FamilyLive.GraphComponent
  import Web.FamilyLive.TreeComponent

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "family:#{family_id}")
    end

    people = People.list_family_members(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    family_graph = FamilyGraph.from(people, relationships, family.id)
    galleries = Galleries.list_galleries(family_id)
    vaults = Memories.list_vaults(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:family_graph, family_graph)
     |> assign(:galleries, galleries)
     |> assign(:vaults, vaults)
     |> assign(:show_new_vault_modal, false)
     |> assign(:vault_form, to_form(Memories.change_vault(%Vault{})))
     |> assign_async(:metrics, fn -> {:ok, %{metrics: Metrics.compute(family_id)}} end,
       supervisor: Ancestry.TaskSupervisor
     )
     |> assign(:graph, nil)
     |> assign(:person_tree, nil)
     |> assign(:view_mode, "graph")
     |> assign(:tree_ancestors, 2)
     |> assign(:tree_descendants, 2)
     |> assign(:tree_other, 1)
     |> assign(:tree_display, "partial")
     |> assign(:partial_settings, %{ancestors: 2, descendants: 2, other: 1})
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
     |> assign(:subfamily_include_partner_ancestors, false)
     |> assign(:show_menu, false)
     |> assign(:show_mobile_tree_sheet, false)
     |> assign(:drawer_open, false)
     |> assign(:show_import_modal, false)
     |> assign(:import_summary, nil)
     |> assign(:import_error, nil)
     |> allow_upload(:csv_file,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
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

    tree_ancestors = parse_depth_param(params, "ancestors", 2)
    tree_descendants = parse_depth_param(params, "descendants", 2)
    tree_other = parse_depth_param(params, "other", 1)
    tree_display = if params["display"] == "complete", do: "complete", else: "partial"
    view_mode = if params["view"] == "tree", do: "tree", else: "graph"

    {tree_ancestors, tree_descendants, tree_other} =
      if tree_display == "complete" do
        {20, 20, 20}
      else
        {tree_ancestors, tree_descendants, tree_other}
      end

    # Clamp other to ancestors
    tree_other = min(tree_other, tree_ancestors)

    depth_opts = [ancestors: tree_ancestors, descendants: tree_descendants, other: tree_other]

    graph =
      if focus_person do
        PersonGraph.build(focus_person, socket.assigns.family_graph, depth_opts)
      else
        nil
      end

    person_tree =
      if focus_person do
        PersonTree.build(focus_person, socket.assigns.family_graph, depth_opts)
      else
        nil
      end

    partial_settings =
      if tree_display == "partial" do
        %{ancestors: tree_ancestors, descendants: tree_descendants, other: tree_other}
      else
        socket.assigns.partial_settings
      end

    socket =
      socket
      |> assign(:focus_person, focus_person)
      |> assign(:graph, graph)
      |> assign(:person_tree, person_tree)
      |> assign(:tree_ancestors, tree_ancestors)
      |> assign(:tree_descendants, tree_descendants)
      |> assign(:tree_other, tree_other)
      |> assign(:tree_display, tree_display)
      |> assign(:partial_settings, partial_settings)
      |> assign(
        :print_url,
        build_print_url(
          socket,
          focus_person,
          tree_display,
          tree_ancestors,
          tree_descendants,
          tree_other
        )
      )
      |> assign(:view_mode, view_mode)

    socket = if focus_person, do: push_event(socket, "scroll_to_focus", %{}), else: socket

    {:noreply, socket}
  end

  # Focus person event — re-center tree

  @impl true
  def handle_event("focus_person", %{"id" => id}, socket) do
    person_id = String.to_integer(id)

    if socket.assigns.focus_person && socket.assigns.focus_person.id == person_id do
      # Already focused — navigate to profile (second tap)
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/org/#{socket.assigns.current_scope.organization.id}/people/#{person_id}?from_family=#{socket.assigns.family.id}"
       )}
    else
      # First tap — focus this person
      {:noreply, push_patch(socket, to: family_path(socket, id))}
    end
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

        # Update graph view to reflect new default person
        {focus_person, graph} =
          case socket.assigns.default_person_id do
            nil ->
              {nil, nil}

            person_id ->
              person = Enum.find(socket.assigns.people, &(&1.id == person_id))

              graph =
                if person do
                  PersonGraph.build(person, socket.assigns.family_graph,
                    ancestors: socket.assigns.tree_ancestors,
                    descendants: socket.assigns.tree_descendants,
                    other: socket.assigns.tree_other
                  )
                else
                  nil
                end

              {person, graph}
          end

        {:noreply,
         socket
         |> assign(:family, family)
         |> assign(:editing, false)
         |> assign(:form, to_form(Families.change_family(family)))
         |> assign(:focus_person, focus_person)
         |> assign(:graph, graph)}

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

  # Vault management

  def handle_event("open_new_vault_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_vault_modal, true)
     |> assign(:vault_form, to_form(Memories.change_vault(%Vault{})))}
  end

  def handle_event("close_new_vault_modal", _, socket) do
    {:noreply, assign(socket, :show_new_vault_modal, false)}
  end

  def handle_event("validate_vault", %{"vault" => params}, socket) do
    changeset =
      %Vault{}
      |> Memories.change_vault(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :vault_form, to_form(changeset))}
  end

  def handle_event("save_vault", %{"vault" => params}, socket) do
    case Memories.create_vault(socket.assigns.family, params) do
      {:ok, _vault} ->
        vaults = Memories.list_vaults(socket.assigns.family.id)

        {:noreply,
         socket
         |> assign(:show_new_vault_modal, false)
         |> assign(:vaults, vaults)}

      {:error, changeset} ->
        {:noreply, assign(socket, :vault_form, to_form(changeset))}
    end
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
        socket = refresh_graph(socket)
        metrics = Metrics.compute(family.id)

        {:noreply,
         socket
         |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))
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

  # Meatball menu

  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
  end

  def handle_event("close_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, false)}
  end

  # CSV import

  def handle_event("open_import", _, socket) do
    {:noreply,
     socket
     |> assign(:show_import_modal, true)
     |> assign(:import_summary, nil)
     |> assign(:import_error, nil)}
  end

  def handle_event("close_import", _, socket) do
    family = socket.assigns.family
    socket = refresh_graph(socket)
    metrics = Metrics.compute(family.id)

    {:noreply,
     socket
     |> assign(:show_import_modal, false)
     |> assign(:import_summary, nil)
     |> assign(:import_error, nil)
     |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))}
  end

  def handle_event("validate_import", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("import_csv", _params, socket) do
    family = socket.assigns.family

    [result] =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
        try do
          {:ok, Ancestry.Import.import_csv_for_family(:family_echo, family, path)}
        rescue
          e in [NimbleCSV.ParseError] ->
            {:ok,
             {:error, gettext("Could not parse CSV file: %{error}", error: Exception.message(e))}}

          _e in [MatchError] ->
            {:ok, {:error, gettext("CSV file is empty or has no data rows")}}

          _ ->
            {:ok, {:error, gettext("Could not parse CSV file")}}
        end
      end)

    case result do
      {:ok, summary} ->
        {:noreply, assign(socket, :import_summary, summary)}

      {:error, reason} ->
        {:noreply, assign(socket, :import_error, reason)}
    end
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
         |> put_flash(:error, gettext("Failed to create subfamily"))
         |> assign(:show_create_subfamily_modal, false)}
    end
  end

  # Tree depth controls

  def handle_event("step_depth", %{"field" => field, "dir" => dir}, socket)
      when field in ~w(ancestors descendants other) do
    current = Map.get(socket.assigns, :"tree_#{field}")
    max = if field == "other", do: socket.assigns.tree_ancestors, else: 20
    new_value = if dir == "up", do: min(current + 1, max), else: max(current - 1, 0)

    overrides = %{String.to_existing_atom(field) => new_value}
    person_id = socket.assigns.focus_person && socket.assigns.focus_person.id

    {:noreply, push_patch(socket, to: family_path(socket, person_id, overrides))}
  end

  def handle_event("toggle_display", %{"display" => display}, socket) do
    person_id = socket.assigns.focus_person && socket.assigns.focus_person.id

    case display do
      "complete" ->
        {:noreply,
         push_patch(socket,
           to:
             family_path(socket, person_id, %{
               ancestors: 20,
               descendants: 20,
               other: 20,
               display: "complete"
             })
         )}

      "partial" ->
        ps = socket.assigns.partial_settings

        {:noreply,
         push_patch(socket,
           to:
             family_path(socket, person_id, %{
               ancestors: ps.ancestors,
               descendants: ps.descendants,
               other: ps.other,
               display: "partial"
             })
         )}
    end
  end

  def handle_event("switch_view", %{"view" => view}, socket) do
    person_id = socket.assigns.focus_person && socket.assigns.focus_person.id
    {:noreply, push_patch(socket, to: family_path(socket, person_id, %{view: view}))}
  end

  # Mobile tree sheet

  def handle_event("open_mobile_tree_sheet", _, socket) do
    {:noreply, assign(socket, :show_mobile_tree_sheet, true)}
  end

  def handle_event("close_mobile_tree_sheet", _, socket) do
    {:noreply, assign(socket, :show_mobile_tree_sheet, false)}
  end

  def handle_event("toggle_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_open, !socket.assigns.drawer_open)}
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
    {:noreply, push_patch(socket, to: family_path(socket, person_id))}
  end

  def handle_info({:relationship_saved, _type, _person}, socket) do
    family = socket.assigns.family
    socket = refresh_graph(socket)
    metrics = Metrics.compute(family.id)

    {:noreply,
     socket
     |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))
     |> assign(:adding_relationship, nil)
     |> put_flash(:info, gettext("Relationship added"))}
  end

  def handle_info({:relationship_error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # assign_async spawns linked tasks that send :EXIT on completion
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  # Private helpers

  defp find_person(people, person_id) do
    Enum.find(people, &(&1.id == person_id)) || People.get_person!(person_id)
  end

  defp get_default_person_id(family_id) do
    case People.get_default_person(family_id) do
      nil -> nil
      person -> person.id
    end
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 10MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .csv files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Only one file can be uploaded")
  defp upload_error_to_string(err), do: gettext("Upload error: %{error}", error: inspect(err))

  defp refresh_graph(socket) do
    family_id = socket.assigns.family.id
    people = People.list_family_members(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    family_graph = FamilyGraph.from(people, relationships, family_id)

    focus_person =
      case socket.assigns.focus_person do
        nil -> nil
        fp -> Enum.find(people, &(&1.id == fp.id))
      end

    depth_opts = [
      ancestors: socket.assigns.tree_ancestors,
      descendants: socket.assigns.tree_descendants,
      other: socket.assigns.tree_other
    ]

    graph =
      if focus_person do
        PersonGraph.build(focus_person, family_graph, depth_opts)
      end

    person_tree =
      if focus_person do
        PersonTree.build(focus_person, family_graph, depth_opts)
      end

    socket
    |> assign(:people, people)
    |> assign(:family_graph, family_graph)
    |> assign(:focus_person, focus_person)
    |> assign(:graph, graph)
    |> assign(:person_tree, person_tree)
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true

  defp tree_stepper(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-xs text-ds-on-surface font-ds-body w-14">{@label}</span>
      <button
        type="button"
        phx-click="step_depth"
        phx-value-field={@name}
        phx-value-dir="down"
        disabled={@value <= 0}
        class="size-6 flex items-center justify-center rounded-sm bg-ds-surface-highest text-ds-on-surface hover:bg-ds-outline-variant/40 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
      >
        <.icon name="hero-minus" class="size-3" />
      </button>
      <span class="text-xs text-ds-on-surface font-ds-body font-semibold w-4 text-center">
        {@value}
      </span>
      <button
        type="button"
        phx-click="step_depth"
        phx-value-field={@name}
        phx-value-dir="up"
        disabled={@value >= @max}
        class="size-6 flex items-center justify-center rounded-sm bg-ds-surface-highest text-ds-on-surface hover:bg-ds-outline-variant/40 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
      >
        <.icon name="hero-plus" class="size-3" />
      </button>
    </div>
    """
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

  defp parse_depth_param(params, key, default) do
    case params[key] do
      nil -> default
      val -> val |> String.to_integer() |> max(0) |> min(20)
    end
  end

  defp build_print_url(
         socket,
         focus_person,
         tree_display,
         tree_ancestors,
         tree_descendants,
         tree_other
       ) do
    case socket.assigns do
      %{current_scope: %{organization: %{id: org_id}}, family: %{id: family_id}} ->
        params = %{}

        params =
          if focus_person,
            do: Map.put(params, :person, focus_person.id),
            else: params

        params =
          if tree_display == "complete" do
            Map.put(params, :display, "complete")
          else
            params
            |> Map.put(:ancestors, tree_ancestors)
            |> Map.put(:descendants, tree_descendants)
            |> Map.put(:other, tree_other)
          end

        ~p"/org/#{org_id}/families/#{family_id}/print?#{params}"

      _ ->
        "#"
    end
  end

  defp family_path(socket, person_id, overrides \\ %{}) do
    base =
      ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}"

    ancestors = Map.get(overrides, :ancestors, socket.assigns.tree_ancestors)
    descendants = Map.get(overrides, :descendants, socket.assigns.tree_descendants)
    other = Map.get(overrides, :other, socket.assigns.tree_other)
    display = Map.get(overrides, :display, socket.assigns.tree_display)
    view = Map.get(overrides, :view, socket.assigns.view_mode)

    params = %{}
    params = if person_id, do: Map.put(params, :person, person_id), else: params
    params = if ancestors != 2, do: Map.put(params, :ancestors, ancestors), else: params
    params = if descendants != 2, do: Map.put(params, :descendants, descendants), else: params
    params = if other != 1, do: Map.put(params, :other, other), else: params
    params = if display != "partial", do: Map.put(params, :display, display), else: params
    params = if view != "graph", do: Map.put(params, :view, view), else: params

    if params == %{}, do: base, else: "#{base}?#{URI.encode_query(params)}"
  end
end
