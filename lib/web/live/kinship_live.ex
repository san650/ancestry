defmodule Web.KinshipLive do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Kinship
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)
    people = People.list_people_for_family(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:person_a, nil)
     |> assign(:person_b, nil)
     |> assign(:result, nil)
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
     |> assign(:person_a, person)
     |> assign(:dropdown_a, false)
     |> assign(:search_a, "")
     |> maybe_calculate()}
  end

  def handle_event("select_person_b", %{"id" => id}, socket) do
    person = find_person(socket.assigns.people, id)

    {:noreply,
     socket
     |> assign(:person_b, person)
     |> assign(:dropdown_b, false)
     |> assign(:search_b, "")
     |> maybe_calculate()}
  end

  # --- Clear ---

  def handle_event("clear_a", _, socket) do
    {:noreply,
     socket
     |> assign(:person_a, nil)
     |> assign(:result, nil)}
  end

  def handle_event("clear_b", _, socket) do
    {:noreply,
     socket
     |> assign(:person_b, nil)
     |> assign(:result, nil)}
  end

  # --- Swap ---

  def handle_event("swap", _, socket) do
    {:noreply,
     socket
     |> assign(:person_a, socket.assigns.person_b)
     |> assign(:person_b, socket.assigns.person_a)
     |> maybe_calculate()}
  end

  # --- Close dropdowns (click-away) ---

  def handle_event("close_dropdowns", _, socket) do
    {:noreply,
     socket
     |> assign(:dropdown_a, false)
     |> assign(:dropdown_b, false)}
  end

  # --- Private helpers ---

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
    query_down = String.downcase(String.trim(query))

    people
    |> Enum.reject(&(&1.id == exclude_id))
    |> Enum.filter(fn person ->
      if query_down == "" do
        true
      else
        name = String.downcase(Person.display_name(person))
        String.contains?(name, query_down)
      end
    end)
  end

  defp maybe_calculate(socket) do
    case {socket.assigns.person_a, socket.assigns.person_b} do
      {%Person{id: a_id}, %Person{id: b_id}} ->
        result = Kinship.calculate(a_id, b_id)
        assign(socket, :result, result)

      _ ->
        assign(socket, :result, nil)
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
          class="flex items-center gap-3 p-4 rounded-xl bg-base-200/50 border border-base-300"
          {test_id("kinship-person-#{@side}-selected")}
        >
          <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
            <%= if @person.photo && @person.photo_status == "processed" do %>
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
                alt={Person.display_name(@person)}
                class="w-full h-full object-cover"
              />
            <% else %>
              <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
            <% end %>
          </div>
          <span class="font-medium text-base-content flex-1 truncate">
            {Person.display_name(@person)}
          </span>
          <button
            id={"kinship-person-#{@side}-clear-btn"}
            phx-click={"clear_#{@side}"}
            class="p-1 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
            {test_id("kinship-person-#{@side}-clear")}
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      <% else %>
        <button
          id={"kinship-person-#{@side}-toggle-btn"}
          phx-click={"toggle_dropdown_#{@side}"}
          class="w-full flex items-center gap-3 p-4 rounded-xl border border-dashed border-base-300 text-base-content/40 hover:border-primary/50 hover:text-primary transition-colors"
          {test_id("kinship-person-#{@side}-toggle")}
        >
          <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center bg-base-200">
            <.icon name="hero-user-plus" class="w-5 h-5" />
          </div>
          <span class="font-medium">Select a person...</span>
        </button>
      <% end %>

      <%= if @dropdown_open do %>
        <div class="absolute z-20 top-full left-0 right-0 mt-2 rounded-xl bg-base-100 border border-base-300 shadow-xl overflow-hidden">
          <div class="p-2">
            <input
              id={"kinship-person-#{@side}-search-input"}
              type="text"
              value={@search}
              placeholder="Search..."
              phx-keyup={"filter_#{@side}"}
              phx-debounce="200"
              autofocus
              class="input input-bordered input-sm w-full"
              {test_id("kinship-person-#{@side}-search")}
            />
          </div>
          <div class="max-h-56 overflow-y-auto px-1 pb-1">
            <%= if @filtered == [] do %>
              <p class="text-sm text-base-content/40 text-center py-4">No people found</p>
            <% else %>
              <%= for person <- @filtered do %>
                <button
                  id={"kinship-person-#{@side}-option-#{person.id}-btn"}
                  phx-click={"select_person_#{@side}"}
                  phx-value-id={person.id}
                  class="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                  {test_id("kinship-person-#{@side}-option-#{person.id}")}
                >
                  <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
                    <%= if person.photo && person.photo_status == "processed" do %>
                      <img
                        src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                        alt={Person.display_name(person)}
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <.icon name="hero-user" class="w-4 h-4 text-base-content/20" />
                    <% end %>
                  </div>
                  <span class="text-sm font-medium text-base-content truncate">
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
end
