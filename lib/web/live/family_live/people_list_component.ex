defmodule Web.FamilyLive.PeopleListComponent do
  use Web, :live_component

  import Web.Components.NavDrawer, only: [toggle_nav_drawer: 0]

  alias Ancestry.People.Person
  alias Phoenix.LiveView.JS

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-ds-body font-semibold text-ds-on-surface-variant uppercase tracking-wider">
          People
        </h3>
        <div class="flex items-center gap-1">
          <button
            id={"#{@id}-link-btn"}
            phx-click="open_search"
            class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
            title="Link existing person"
            {test_id("person-link-btn")}
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4" />
          </button>
          <.link
            id={"#{@id}-add-btn"}
            navigate={~p"/org/#{@organization.id}/families/#{@family_id}/members/new"}
            class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
            title="New member"
            {test_id("person-add-btn")}
          >
            <.icon name="hero-plus" class="w-4 h-4" />
          </.link>
        </div>
      </div>

      <div class="mb-3">
        <input
          id={"#{@id}-filter"}
          type="text"
          placeholder="Filter people..."
          class="w-full px-3 py-2 bg-ds-surface-card text-ds-on-surface border-b-2 border-ds-outline-variant/20 focus:border-ds-primary focus:outline-none font-ds-body text-sm"
          phx-hook="FuzzyFilter"
          data-target={"#{@id}-items"}
          phx-update="ignore"
        />
      </div>

      <div
        id={"#{@id}-items"}
        class="space-y-0.5 max-h-96 overflow-y-auto"
        {test_id("person-list")}
      >
        <%= if @people == [] do %>
          <p class="text-sm text-ds-on-surface-variant py-2">No members yet.</p>
        <% end %>
        <%= for person <- @people do %>
          <div
            class={[
              "flex items-center gap-2 px-2 py-1.5 rounded-ds-sharp transition-colors text-sm group",
              if(person.id == @focus_person_id,
                do: "bg-ds-primary/10",
                else: "hover:bg-ds-surface-highest"
              )
            ]}
            data-filter-name={
              Ancestry.StringUtils.normalize("#{person.surname}, #{person.given_name}")
            }
            {test_id("person-item-#{person.id}")}
          >
            <button
              phx-click={focus_click(assigns, person.id)}
              class="flex items-center gap-2 flex-1 min-w-0 cursor-pointer"
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
              <span class="text-ds-on-surface truncate">
                {person.surname}
                <%= if person.surname && person.given_name do %>
                  ,
                <% end %>
                {person.given_name}
              </span>
            </button>
            <.link
              navigate={~p"/org/#{@organization.id}/people/#{person.id}?from_family=#{@family_id}"}
              class="p-1 rounded text-ds-on-surface-variant/50 hover:text-ds-primary hover:bg-ds-primary/10 transition-colors opacity-0 group-hover:opacity-100 flex-shrink-0"
              title="View details"
            >
              <.icon name="hero-arrow-top-right-on-square-mini" class="w-3.5 h-3.5" />
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Stringify the id explicitly so the existing focus_person handler
  # (which calls String.to_integer/1) keeps working regardless of how
  # JS.push serialises numeric values.
  defp focus_click(%{close_drawer_on_select: true}, person_id) do
    toggle_nav_drawer() |> JS.push("focus_person", value: %{id: to_string(person_id)})
  end

  defp focus_click(_assigns, person_id) do
    JS.push("focus_person", value: %{id: to_string(person_id)})
  end
end
