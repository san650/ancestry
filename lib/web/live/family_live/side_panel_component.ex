defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent
  alias Web.FamilyLive.VaultListComponent

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
              <span class="text-xs text-ds-on-surface-variant">{gettext("Members")}</span>
            </div>
            <div
              class="flex flex-col items-center p-3 rounded-ds-sharp bg-ds-surface-low"
              {test_id("metric-photo-count")}
            >
              <.icon name="hero-photo" class="w-5 h-5 text-ds-secondary mb-1" />
              <span class="text-2xl font-bold text-ds-on-surface">
                {@metrics.result.photo_count}
              </span>
              <span class="text-xs text-ds-on-surface-variant">{gettext("Photos")}</span>
            </div>
          </div>
        </div>

        <div class="border-t border-ds-outline-variant/20"></div>
      <% end %>

      <.live_component
        module={VaultListComponent}
        id={"#{@id}-vault-list"}
        vaults={@vaults}
        family_id={@family_id}
        organization={@organization}
      />

      <div class="border-t border-ds-outline-variant/20"></div>

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
end
