defmodule Web.FamilyLive.PersonSelectorComponent do
  use Web, :live_component

  alias Ancestry.People.Person

  @impl true
  def mount(socket) do
    {:ok, assign(socket, query: "", open: false, filtered_people: [])}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_filtered()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative" phx-click-away="close_selector" phx-target={@myself}>
      <button
        type="button"
        phx-click="toggle_selector"
        phx-target={@myself}
        class="flex items-center gap-2 px-3 py-1.5 rounded-ds-sharp bg-ds-surface-low hover:bg-ds-surface-highest transition-colors text-sm w-full max-w-xs"
      >
        <.icon name="hero-user" class="w-4 h-4 text-ds-on-surface-variant" />
        <span class="truncate font-medium text-ds-on-surface">
          <%= if @focus_person do %>
            {Person.display_name(@focus_person)}
          <% else %>
            Select a person...
          <% end %>
        </span>
        <.icon name="hero-chevron-down" class="w-4 h-4 text-ds-on-surface-variant ml-auto" />
      </button>

      <%= if @open do %>
        <div class="absolute top-full left-0 mt-1 w-full max-w-xs bg-ds-surface-card/80 backdrop-blur-[20px] rounded-ds-sharp shadow-ds-ambient z-50 max-h-80 flex flex-col">
          <div class="p-2 border-b border-ds-outline-variant/20">
            <input
              id={"#{@id}-input"}
              type="text"
              value={@query}
              placeholder="Search people..."
              phx-keyup="filter_people"
              phx-target={@myself}
              phx-debounce="150"
              autofocus
              class="w-full px-3 py-2 bg-ds-surface-card text-ds-on-surface border-b-2 border-ds-outline-variant/20 focus:border-ds-primary focus:outline-none font-ds-body text-sm"
            />
          </div>
          <div class="overflow-y-auto max-h-64">
            <%= if @filtered_people == [] do %>
              <p class="text-sm text-ds-on-surface-variant py-4 text-center">No matches</p>
            <% end %>
            <%= for person <- @filtered_people do %>
              <button
                type="button"
                phx-click="select_person"
                phx-value-id={person.id}
                phx-target={@myself}
                class={[
                  "w-full flex items-center gap-2 px-3 py-2 hover:bg-ds-surface-highest transition-colors text-sm text-left",
                  @focus_person && person.id == @focus_person.id && "bg-ds-primary/10"
                ]}
              >
                <div class="w-6 h-6 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden flex-shrink-0">
                  <%= if person.photo && person.photo_status == "processed" do %>
                    <img
                      src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                      alt={Person.display_name(person)}
                      class="w-full h-full object-cover"
                    />
                  <% else %>
                    <.icon name="hero-user" class="w-3 h-3 text-ds-primary" />
                  <% end %>
                </div>
                <span class="truncate text-ds-on-surface">
                  {Person.display_name(person)}
                </span>
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_selector", _, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open, query: "") |> assign_filtered()}
  end

  def handle_event("close_selector", _, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("filter_people", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_filtered()}
  end

  def handle_event("select_person", %{"id" => id}, socket) do
    send(self(), {:focus_person, String.to_integer(id)})
    {:noreply, assign(socket, open: false, query: "")}
  end

  defp assign_filtered(socket) do
    query = Ancestry.StringUtils.normalize(String.trim(socket.assigns.query))
    people = socket.assigns.people

    filtered =
      if query == "" do
        people
      else
        Enum.filter(people, fn person ->
          name = Ancestry.StringUtils.normalize(Person.display_name(person))
          String.contains?(name, query)
        end)
      end

    assign(socket, :filtered_people, filtered)
  end
end
