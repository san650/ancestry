defmodule Web.KinshipLive do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Kinship
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person
  alias Ancestry.Relationships

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    people = People.list_family_members(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    family_graph = FamilyGraph.from(people, relationships, family.id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:family_graph, family_graph)
     |> assign(:person_a, nil)
     |> assign(:person_b, nil)
     |> assign(:result, nil)
     |> assign(:path_a, [])
     |> assign(:path_b, [])
     |> assign(:search_a, "")
     |> assign(:search_b, "")
     |> assign(:filtered_a, people)
     |> assign(:filtered_b, people)
     |> assign(:dropdown_a, false)
     |> assign(:dropdown_b, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    people = socket.assigns.people

    person_a = resolve_person(params["person_a"], people)
    person_b = resolve_person(params["person_b"], people)

    socket =
      socket
      |> assign(:person_a, person_a)
      |> assign(:person_b, person_b)
      |> maybe_calculate()

    {:noreply, socket}
  end

  # --- Dropdown toggle ---

  @impl true
  def handle_event("toggle_dropdown_a", _, socket) do
    open = !socket.assigns.dropdown_a

    {:noreply,
     socket
     |> assign(:dropdown_a, open)
     |> assign(:dropdown_b, false)
     |> assign(:search_a, "")
     |> assign(:filtered_a, filter_people(socket.assigns.people, "", socket.assigns.person_b))}
  end

  def handle_event("toggle_dropdown_b", _, socket) do
    open = !socket.assigns.dropdown_b

    {:noreply,
     socket
     |> assign(:dropdown_b, open)
     |> assign(:dropdown_a, false)
     |> assign(:search_b, "")
     |> assign(:filtered_b, filter_people(socket.assigns.people, "", socket.assigns.person_a))}
  end

  # --- Search / filter ---

  def handle_event("filter_a", %{"value" => query}, socket) do
    filtered = filter_people(socket.assigns.people, query, socket.assigns.person_b)

    {:noreply,
     socket
     |> assign(:search_a, query)
     |> assign(:filtered_a, filtered)}
  end

  def handle_event("filter_b", %{"value" => query}, socket) do
    filtered = filter_people(socket.assigns.people, query, socket.assigns.person_a)

    {:noreply,
     socket
     |> assign(:search_b, query)
     |> assign(:filtered_b, filtered)}
  end

  # --- Select person ---

  def handle_event("select_person_a", %{"id" => id}, socket) do
    person = find_person(socket.assigns.people, id)

    {:noreply,
     socket
     |> assign(:dropdown_a, false)
     |> assign(:search_a, "")
     |> push_kinship_patch(person, socket.assigns.person_b)}
  end

  def handle_event("select_person_b", %{"id" => id}, socket) do
    person = find_person(socket.assigns.people, id)

    {:noreply,
     socket
     |> assign(:dropdown_b, false)
     |> assign(:search_b, "")
     |> push_kinship_patch(socket.assigns.person_a, person)}
  end

  # --- Clear ---

  def handle_event("clear_a", _, socket) do
    {:noreply, push_kinship_patch(socket, nil, socket.assigns.person_b)}
  end

  def handle_event("clear_b", _, socket) do
    {:noreply, push_kinship_patch(socket, socket.assigns.person_a, nil)}
  end

  # --- Swap ---

  def handle_event("swap", _, socket) do
    {:noreply, push_kinship_patch(socket, socket.assigns.person_b, socket.assigns.person_a)}
  end

  # --- Private helpers ---

  defp push_kinship_patch(socket, person_a, person_b) do
    params =
      %{}
      |> then(fn p -> if person_a, do: Map.put(p, :person_a, person_a.id), else: p end)
      |> then(fn p -> if person_b, do: Map.put(p, :person_b, person_b.id), else: p end)

    push_patch(socket,
      to:
        ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}/kinship?#{params}"
    )
  end

  defp resolve_person(nil, _people), do: nil
  defp resolve_person("", _people), do: nil

  defp resolve_person(id_str, people) do
    case Integer.parse(id_str) do
      {id, ""} -> Enum.find(people, &(&1.id == id))
      _ -> nil
    end
  end

  defp find_person(people, id) when is_binary(id) do
    case Integer.parse(id) do
      {person_id, ""} -> Enum.find(people, &(&1.id == person_id))
      _ -> nil
    end
  end

  defp filter_people(people, query, exclude_person) do
    exclude_id = if exclude_person, do: exclude_person.id, else: nil
    query_normalized = Ancestry.StringUtils.normalize(String.trim(query))

    people
    |> Enum.reject(&(&1.id == exclude_id))
    |> Enum.filter(fn person ->
      if query_normalized == "" do
        true
      else
        name = Ancestry.StringUtils.normalize(Person.display_name(person))
        String.contains?(name, query_normalized)
      end
    end)
  end

  defp maybe_calculate(socket) do
    case {socket.assigns.person_a, socket.assigns.person_b} do
      {%Person{id: a_id}, %Person{id: b_id}} ->
        case Kinship.calculate(a_id, b_id, socket.assigns.family_graph) do
          {:ok, result} ->
            path_a = Enum.slice(result.path, 0, result.steps_a + 1) |> Enum.reverse()
            path_b = Enum.slice(result.path, result.steps_a, length(result.path) - result.steps_a)

            socket
            |> assign(:result, {:ok, result})
            |> assign(:path_a, path_a)
            |> assign(:path_b, path_b)

          error ->
            socket
            |> assign(:result, error)
            |> assign(:path_a, [])
            |> assign(:path_b, [])
        end

      _ ->
        assign(socket, result: nil, path_a: [], path_b: [])
    end
  end

  # --- Function components ---

  attr :side, :string, required: true
  attr :person, :any, required: true
  attr :dropdown_open, :boolean, required: true
  attr :search, :string, required: true
  attr :filtered, :list, required: true

  defp person_selector(assigns) do
    ~H"""
    <div class="relative">
      <%= if @person do %>
        <div
          class="flex items-center gap-3 p-4 rounded-cm bg-cm-surface/50 border-2 border-cm-black"
          {test_id("kinship-person-#{@side}-selected")}
        >
          <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-cm-surface">
            <%= if @person.photo && @person.photo_status == "processed" do %>
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
                alt={Person.display_name(@person)}
                class="w-full h-full object-cover"
              />
            <% else %>
              <.icon name="hero-user" class="w-5 h-5 text-cm-black/20" />
            <% end %>
          </div>
          <span class="font-cm-body font-medium text-cm-black flex-1 truncate">
            {Person.display_name(@person)}
          </span>
          <button
            id={"kinship-person-#{@side}-clear-btn"}
            phx-click={"clear_#{@side}"}
            class="p-1 rounded-lg text-cm-black/40 hover:text-cm-black hover:bg-cm-surface transition-colors"
            {test_id("kinship-person-#{@side}-clear")}
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      <% else %>
        <button
          id={"kinship-person-#{@side}-toggle-btn"}
          phx-click={"toggle_dropdown_#{@side}"}
          class="w-full flex items-center gap-3 p-4 rounded-cm border-2 border-dashed border-cm-border text-cm-black/40 hover:border-cm-indigo hover:text-cm-indigo transition-colors"
          {test_id("kinship-person-#{@side}-toggle")}
        >
          <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center bg-cm-surface">
            <.icon name="hero-user-plus" class="w-5 h-5" />
          </div>
          <span class="font-medium">{gettext("Select a person...")}</span>
        </button>
      <% end %>

      <%= if @dropdown_open do %>
        <div
          class="absolute z-20 top-full left-0 right-0 mt-2 rounded-cm bg-cm-white border-2 border-cm-black overflow-hidden"
          phx-click-away={"toggle_dropdown_#{@side}"}
        >
          <div class="p-2">
            <input
              id={"kinship-person-#{@side}-search-input"}
              type="text"
              value={@search}
              placeholder={gettext("Search...")}
              phx-keyup={"filter_#{@side}"}
              phx-debounce="200"
              phx-mounted={JS.focus()}
              class="w-full border-2 border-cm-black rounded-cm px-3 py-1.5 text-sm font-cm-body text-cm-black bg-cm-white focus:outline-none focus:ring-2 focus:ring-cm-indigo/20"
              {test_id("kinship-person-#{@side}-search")}
            />
          </div>
          <div class="max-h-56 overflow-y-auto px-1 pb-1">
            <%= if @filtered == [] do %>
              <p class="text-sm text-cm-black/40 text-center py-4">
                {gettext("No people found")}
              </p>
            <% else %>
              <%= for person <- @filtered do %>
                <button
                  id={"kinship-person-#{@side}-option-#{person.id}-btn"}
                  phx-click={"select_person_#{@side}"}
                  phx-value-id={person.id}
                  class="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-cm-surface transition-colors text-left"
                  {test_id("kinship-person-#{@side}-option-#{person.id}")}
                >
                  <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-cm-surface">
                    <%= if person.photo && person.photo_status == "processed" do %>
                      <img
                        src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                        alt={Person.display_name(person)}
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <.icon name="hero-user" class="w-4 h-4 text-cm-black/20" />
                    <% end %>
                  </div>
                  <span class="text-sm font-medium text-cm-black truncate">
                    {Person.display_name(person)}
                  </span>
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_dna(percentage) do
    if percentage == trunc(percentage) do
      "#{trunc(percentage)}"
    else
      :erlang.float_to_binary(percentage, decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing("0")
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end

  attr :direction, :atom, required: true

  defp arrow_connector(assigns) do
    ~H"""
    <div class="py-1 text-cm-black/50">
      <%= if @direction == :up do %>
        <svg width="16" height="16" viewBox="0 0 16 16" class="mx-auto">
          <path
            d="M8 2 L8 14 M3 7 L8 2 L13 7"
            stroke="currentColor"
            stroke-width="1.5"
            fill="none"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      <% else %>
        <svg width="16" height="16" viewBox="0 0 16 16" class="mx-auto">
          <path
            d="M8 2 L8 14 M3 9 L8 14 L13 9"
            stroke="currentColor"
            stroke-width="1.5"
            fill="none"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      <% end %>
    </div>
    """
  end

  defp fork_connector(assigns) do
    ~H"""
    <div class="w-full max-w-2xl py-1 text-cm-black/50">
      <svg viewBox="0 0 200 40" class="w-full h-10" preserveAspectRatio="none">
        <path
          d="M100 0 L100 15 M100 15 L50 40 M100 15 L150 40"
          stroke="currentColor"
          stroke-width="1.5"
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
    </div>
    """
  end

  attr :person_left, :any, required: true
  attr :person_right, :any, required: true
  attr :label_left, :string, default: nil
  attr :label_right, :string, default: nil
  attr :highlight_left, :boolean, default: false
  attr :highlight_right, :boolean, default: false
  attr :org_id, :any, default: nil
  attr :direction, :atom, default: :horizontal

  defp partner_pair_node(assigns) do
    ~H"""
    <div class={[
      "w-full",
      if(@direction == :vertical,
        do: "flex flex-col items-center gap-1",
        else: "flex items-center gap-2"
      )
    ]}>
      <.link
        navigate={if @org_id, do: ~p"/org/#{@org_id}/people/#{@person_left.id}", else: "#"}
        class={[
          "flex items-center gap-2 px-3 py-2 rounded-cm border-2 min-w-0 hover:transition-shadow",
          if(@direction == :vertical, do: "w-full", else: "flex-1"),
          if(@highlight_left,
            do: "bg-cm-indigo/10 border-cm-indigo",
            else: "bg-cm-surface/50 border-cm-black/20"
          )
        ]}
      >
        <.kinship_person_avatar person={@person_left} />
        <div class="min-w-0 flex-1">
          <p class="font-cm-body font-medium text-sm text-cm-black truncate">
            {Person.display_name(@person_left)}
          </p>
          <%= if @label_left do %>
            <p class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
              {@label_left}
            </p>
          <% end %>
        </div>
      </.link>
      <div class="shrink-0 text-cm-text-muted/50">
        <.icon
          name="hero-arrows-right-left"
          class={["w-4 h-4", if(@direction == :vertical, do: "rotate-90")]}
        />
      </div>
      <.link
        navigate={if @org_id, do: ~p"/org/#{@org_id}/people/#{@person_right.id}", else: "#"}
        class={[
          "flex items-center gap-2 px-3 py-2 rounded-cm border-2 min-w-0 hover:transition-shadow",
          if(@direction == :vertical, do: "w-full", else: "flex-1"),
          if(@highlight_right,
            do: "bg-cm-indigo/10 border-cm-indigo",
            else: "bg-cm-surface/50 border-cm-black/20"
          )
        ]}
      >
        <.kinship_person_avatar person={@person_right} />
        <div class="min-w-0 flex-1">
          <p class="font-cm-body font-medium text-sm text-cm-black truncate">
            {Person.display_name(@person_right)}
          </p>
          <%= if @label_right do %>
            <p class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
              {@label_right}
            </p>
          <% end %>
        </div>
      </.link>
    </div>
    """
  end

  attr :person, :any, required: true
  attr :label, :string, default: nil
  attr :highlight, :boolean, default: false
  attr :extra_label, :string, default: nil
  attr :org_id, :any, required: true

  defp kinship_person_node(assigns) do
    ~H"""
    <.link
      navigate={~p"/org/#{@org_id}/people/#{@person.id}"}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded-cm border-2 w-full hover:transition-shadow",
        if(@highlight,
          do: "bg-cm-indigo/10 border-cm-indigo",
          else: "bg-cm-surface/50 border-cm-black/20"
        )
      ]}
    >
      <.kinship_person_avatar person={@person} />
      <div class="min-w-0 flex-1">
        <p class="font-cm-body font-medium text-sm text-cm-black truncate">
          {Person.display_name(@person)}
        </p>
        <%= if @label do %>
          <p class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">{@label}</p>
        <% end %>
        <%= if @extra_label do %>
          <p class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
            {@extra_label}
          </p>
        <% end %>
      </div>
    </.link>
    """
  end

  attr :person, :any, required: true

  defp kinship_person_avatar(assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-cm-surface">
      <%= if @person.photo && @person.photo_status == "processed" do %>
        <img
          src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
          alt={Ancestry.People.Person.display_name(@person)}
          class="w-full h-full object-cover"
        />
      <% else %>
        <.icon name="hero-user" class="w-4 h-4 text-cm-black/20" />
      <% end %>
    </div>
    """
  end
end
