defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Ancestry.People.Person
  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:close_drawer_on_select, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col p-4 gap-6">
      <%!-- Metrics Section: desktop only --%>
      <%= if @metrics.ok? && @metrics.result.people_count > 0 do %>
        <div class="hidden lg:block space-y-4">
          <%!-- People & Photo counts --%>
          <div class="grid grid-cols-2 gap-3">
            <div
              class="flex flex-col items-center p-3 rounded-ds-sharp bg-ds-surface-low"
              {test_id("metric-people-count")}
            >
              <.icon name="hero-users" class="w-5 h-5 text-ds-primary mb-1" />
              <span class="text-2xl font-bold text-ds-on-surface">
                {@metrics.result.people_count}
              </span>
              <span class="text-xs text-ds-on-surface-variant">Members</span>
            </div>
            <div
              class="flex flex-col items-center p-3 rounded-ds-sharp bg-ds-surface-low"
              {test_id("metric-photo-count")}
            >
              <.icon name="hero-photo" class="w-5 h-5 text-ds-secondary mb-1" />
              <span class="text-2xl font-bold text-ds-on-surface">
                {@metrics.result.photo_count}
              </span>
              <span class="text-xs text-ds-on-surface-variant">Photos</span>
            </div>
          </div>

          <%!-- Generations --%>
          <%= if @metrics.result.generations do %>
            <div
              class="flex flex-col items-center p-3 rounded-ds-sharp bg-ds-surface-low"
              {test_id("metric-generations")}
            >
              <span class="text-xs text-ds-on-surface-variant uppercase tracking-wider mb-2">
                Lineage
              </span>
              <.metric_person_card person={@metrics.result.generations.root} label="Root ancestor" />
              <div class="flex flex-col items-center my-1">
                <div class="w-px h-3 bg-ds-on-surface-variant/50"></div>
                <span class="text-sm font-semibold text-ds-primary py-0.5">
                  {@metrics.result.generations.count} generations
                </span>
                <div class="w-px h-3 bg-ds-on-surface-variant/50"></div>
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
              class="flex flex-col items-center p-3 rounded-ds-sharp bg-ds-surface-low"
              {test_id("metric-oldest-person")}
            >
              <span class="text-xs text-ds-on-surface-variant uppercase tracking-wider mb-2">
                Oldest Record
              </span>
              <.metric_person_card
                person={@metrics.result.oldest_person.person}
                label={age_label(@metrics.result.oldest_person)}
              />
            </div>
          <% end %>
        </div>

        <div class="border-t border-ds-outline-variant/20"></div>
      <% end %>

      <.live_component
        module={GalleryListComponent}
        id={"#{@id}-gallery-list"}
        galleries={@galleries}
        family_id={@family_id}
        organization={@organization}
      />

      <div class="border-t border-ds-outline-variant/20"></div>

      <.live_component
        module={PeopleListComponent}
        id={"#{@id}-people-list"}
        people={@people}
        family_id={@family_id}
        organization={@organization}
        focus_person_id={@focus_person_id}
        close_drawer_on_select={@close_drawer_on_select}
      />
    </div>
    """
  end

  attr :person, :map, required: true
  attr :label, :string, required: true

  defp metric_person_card(assigns) do
    ~H"""
    <button
      phx-click="focus_person"
      phx-value-id={@person.id}
      class="flex items-center gap-2 px-3 py-2 rounded-ds-sharp hover:bg-ds-surface-highest transition-colors w-full group"
    >
      <div class="w-8 h-8 rounded-full bg-ds-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <span class="text-xs font-semibold text-ds-primary">
            {initials(@person)}
          </span>
        <% end %>
      </div>
      <div class="min-w-0 text-left">
        <p class="text-sm font-medium text-ds-on-surface truncate group-hover:text-ds-primary transition-colors">
          {Person.display_name(@person)}
        </p>
        <p class="text-xs text-ds-on-surface-variant">{@label}</p>
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
