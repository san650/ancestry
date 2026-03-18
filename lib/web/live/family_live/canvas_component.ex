defmodule Web.FamilyLive.CanvasComponent do
  use Web, :live_component

  alias Ancestry.People.Person
  alias Web.FamilyLive.TreeComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="overflow-auto flex-1 min-h-0 p-4">
      <%= if @grid.rows > 0 do %>
        <.live_component
          module={TreeComponent}
          id="tree-main"
          grid={@grid}
          graph={@graph}
          family_id={@family_id}
        />
      <% end %>

      <%= if @graph.unconnected != [] do %>
        <div class="mt-8">
          <h3 class="text-sm font-medium text-base-content/40 mb-3">Not connected to tree</h3>
          <div class="flex flex-wrap gap-4 lg:flex-row flex-col">
            <%= for person <- @graph.unconnected do %>
              <.link navigate={~p"/families/#{@family_id}/members/#{person.id}"}>
                <div class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-200/50 hover:bg-base-200 transition-colors">
                  <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden">
                    <%= if person.photo && person.photo_status == "processed" do %>
                      <img
                        src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                        alt={Person.display_name(person)}
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <.icon name="hero-user" class="w-4 h-4 text-primary" />
                    <% end %>
                  </div>
                  <span class="text-sm text-base-content">{Person.display_name(person)}</span>
                </div>
              </.link>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @grid.rows == 0 and @graph.unconnected == [] do %>
        <div class="flex items-center justify-center h-48 text-base-content/40">
          No members yet. Add members from the side panel.
        </div>
      <% end %>
    </div>
    """
  end
end
