defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Ancestry.People.Person
  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent

  @impl true
  def render(assigns) do
    ~H"""
    <aside id={@id} class="bg-base-100 flex flex-col p-4 gap-6">
      <%!-- Metrics Section --%>
      <%= if @metrics.ok? && @metrics.result.people_count > 0 do %>
        <div class="space-y-4">
          <%!-- People & Photo counts --%>
          <div class="grid grid-cols-2 gap-3">
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-people-count")}
            >
              <.icon name="hero-users" class="w-5 h-5 text-primary mb-1" />
              <span class="text-2xl font-bold text-base-content">{@metrics.result.people_count}</span>
              <span class="text-xs text-base-content/50">Members</span>
            </div>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-photo-count")}
            >
              <.icon name="hero-photo" class="w-5 h-5 text-secondary mb-1" />
              <span class="text-2xl font-bold text-base-content">{@metrics.result.photo_count}</span>
              <span class="text-xs text-base-content/50">Photos</span>
            </div>
          </div>

          <%!-- Generations --%>
          <%= if @metrics.result.generations do %>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-generations")}
            >
              <span class="text-xs text-base-content/50 uppercase tracking-wider mb-2">
                Lineage
              </span>
              <.metric_person_card person={@metrics.result.generations.root} label="Root ancestor" />
              <div class="flex flex-col items-center my-1">
                <div class="w-px h-3 bg-base-content/20"></div>
                <span class="text-sm font-semibold text-primary py-0.5">
                  {@metrics.result.generations.count} generations
                </span>
                <div class="w-px h-3 bg-base-content/20"></div>
              </div>
              <.metric_person_card
                person={@metrics.result.generations.leaf}
                label="Latest descendant"
              />
            </div>
          <% end %>

          <%!-- Oldest Person --%>
          <%= if @metrics.result.oldest_person do %>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-oldest-person")}
            >
              <span class="text-xs text-base-content/50 uppercase tracking-wider mb-2">
                Oldest Record
              </span>
              <.metric_person_card
                person={@metrics.result.oldest_person.person}
                label={age_label(@metrics.result.oldest_person)}
              />
            </div>
          <% end %>
        </div>

        <div class="border-t border-base-200"></div>
      <% end %>

      <.live_component
        module={GalleryListComponent}
        id="gallery-list"
        galleries={@galleries}
        family_id={@family_id}
      />

      <div class="border-t border-base-200"></div>

      <.live_component
        module={PeopleListComponent}
        id="people-list"
        people={@people}
        family_id={@family_id}
        focus_person_id={@focus_person_id}
      />
    </aside>
    """
  end

  attr :person, :map, required: true
  attr :label, :string, required: true

  defp metric_person_card(assigns) do
    ~H"""
    <button
      phx-click="focus_person"
      phx-value-id={@person.id}
      class="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-base-300/50 transition-colors w-full group"
    >
      <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <span class="text-xs font-semibold text-primary">
            {initials(@person)}
          </span>
        <% end %>
      </div>
      <div class="min-w-0 text-left">
        <p class="text-sm font-medium text-base-content truncate group-hover:text-primary transition-colors">
          {Person.display_name(@person)}
        </p>
        <p class="text-xs text-base-content/50">{@label}</p>
      </div>
    </button>
    """
  end

  defp initials(%Person{given_name: g, surname: s}) do
    [g, s]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp age_label(%{person: person, age: age}) do
    if person.deceased do
      "was #{age} years"
    else
      "#{age} years"
    end
  end
end
