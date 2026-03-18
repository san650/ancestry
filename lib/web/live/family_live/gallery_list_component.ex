defmodule Web.FamilyLive.GalleryListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
          Galleries
        </h3>
        <button
          id="open-new-gallery-btn"
          phx-click="open_new_gallery_modal"
          class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div id="galleries" class="space-y-1">
        <%= if @galleries == [] do %>
          <div class="text-sm text-base-content/40 py-2">
            No galleries yet.
          </div>
        <% end %>
        <.link
          :for={gallery <- @galleries}
          id={"gallery-#{gallery.id}"}
          navigate={~p"/families/#{@family_id}/galleries/#{gallery.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-base-200 transition-colors text-sm text-base-content"
        >
          <.icon name="hero-photo" class="w-4 h-4 text-base-content/40" />
          <span class="truncate" data-gallery-name>{gallery.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
