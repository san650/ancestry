defmodule Web.FamilyLive.PeopleListComponent do
  use Web, :live_component

  alias Ancestry.People.Person

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">People</h3>
        <div class="flex items-center gap-1">
          <button
            id="link-existing-btn"
            phx-click="open_search"
            class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
            title="Link existing person"
            {test_id("person-link-btn")}
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4" />
          </button>
          <.link
            id="add-member-btn"
            navigate={~p"/families/#{@family_id}/members/new"}
            class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
            title="New member"
            {test_id("person-add-btn")}
          >
            <.icon name="hero-plus" class="w-4 h-4" />
          </.link>
        </div>
      </div>

      <div class="mb-3">
        <input
          id="people-filter-input"
          type="text"
          placeholder="Filter people..."
          class="input input-bordered input-sm w-full"
          phx-hook="FuzzyFilter"
          data-target="people-list-items"
          phx-update="ignore"
        />
      </div>

      <div
        id="people-list-items"
        class="space-y-0.5 max-h-96 overflow-y-auto"
        {test_id("person-list")}
      >
        <%= if @people == [] do %>
          <p class="text-sm text-base-content/40 py-2">No members yet.</p>
        <% end %>
        <%= for person <- @people do %>
          <div
            class={[
              "flex items-center gap-2 px-2 py-1.5 rounded-lg transition-colors text-sm group",
              if(person.id == @focus_person_id, do: "bg-primary/10", else: "hover:bg-base-200")
            ]}
            data-filter-name={String.downcase("#{person.surname}, #{person.given_name}")}
            {test_id("person-item-#{person.id}")}
          >
            <button
              phx-click="focus_person"
              phx-value-id={person.id}
              class="flex items-center gap-2 flex-1 min-w-0 cursor-pointer"
            >
              <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden flex-shrink-0">
                <%= if person.photo && person.photo_status == "processed" do %>
                  <img
                    src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                    alt={Person.display_name(person)}
                    class="w-full h-full object-cover"
                  />
                <% else %>
                  <.icon name="hero-user" class="w-3 h-3 text-primary" />
                <% end %>
              </div>
              <span class="text-base-content truncate">
                {person.surname}
                <%= if person.surname && person.given_name do %>
                  ,
                <% end %>
                {person.given_name}
              </span>
            </button>
            <.link
              navigate={~p"/families/#{@family_id}/members/#{person.id}"}
              class="p-1 rounded text-base-content/20 hover:text-primary hover:bg-primary/10 transition-colors opacity-0 group-hover:opacity-100 flex-shrink-0"
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
end
