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
        <h3 class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
          {gettext("People")}
        </h3>
        <div class="flex items-center gap-1">
          <button
            id={"#{@id}-link-btn"}
            phx-click="open_search"
            class="p-1 rounded text-cm-text-muted hover:text-cm-indigo hover:bg-cm-indigo/10 transition-colors"
            title={gettext("Link existing person")}
            {test_id("person-link-btn")}
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4" />
          </button>
          <.link
            id={"#{@id}-add-btn"}
            navigate={~p"/org/#{@organization.id}/families/#{@family_id}/members/new"}
            class="p-1 rounded text-cm-text-muted hover:text-cm-indigo hover:bg-cm-indigo/10 transition-colors"
            title={gettext("New member")}
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
          placeholder={gettext("Filter people...")}
          class="w-full px-3 py-2 bg-cm-white text-cm-black border-b-2 border-cm-border/20 focus:border-cm-indigo focus:outline-none font-cm-body text-sm"
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
          <p class="text-sm text-cm-text-muted py-2">{gettext("No members yet.")}</p>
        <% end %>
        <%= for person <- @people do %>
          <div
            class={[
              "flex items-center gap-2 px-2 py-1.5 rounded-cm transition-colors text-sm group",
              if(person.id == @focus_person_id,
                do: "bg-cm-indigo/10",
                else: "hover:bg-cm-surface"
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
              <div class="w-6 h-6 rounded-full bg-cm-indigo/10 flex items-center justify-center overflow-hidden flex-shrink-0">
                <%= if person.photo && person.photo_status == "processed" do %>
                  <img
                    src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                    alt={Person.display_name(person)}
                    class="w-full h-full object-cover"
                  />
                <% else %>
                  <.icon name="hero-user" class="w-3 h-3 text-cm-indigo" />
                <% end %>
              </div>
              <span class="text-cm-black truncate">
                {person.surname}
                <%= if person.surname && person.given_name do %>
                  ,
                <% end %>
                {person.given_name}
              </span>
            </button>
            <.link
              navigate={~p"/org/#{@organization.id}/people/#{person.id}?from_family=#{@family_id}"}
              class="p-1 rounded text-cm-text-muted/50 hover:text-cm-indigo hover:bg-cm-indigo/10 transition-colors opacity-0 group-hover:opacity-100 flex-shrink-0"
              title={gettext("View details")}
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
