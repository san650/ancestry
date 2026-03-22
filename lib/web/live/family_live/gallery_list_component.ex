defmodule Web.FamilyLive.GalleryListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-ds-body font-semibold text-ds-on-surface-variant uppercase tracking-wider">
          Galleries
        </h3>
        <button
          id="open-new-gallery-btn"
          phx-click="open_new_gallery_modal"
          class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div id="galleries" class="space-y-1">
        <%= if @galleries == [] do %>
          <div class="text-sm text-ds-on-surface-variant py-2">
            No galleries yet.
          </div>
        <% end %>
        <.link
          :for={gallery <- @galleries}
          id={"gallery-#{gallery.id}"}
          navigate={~p"/org/#{@organization.id}/families/#{@family_id}/galleries/#{gallery.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-ds-sharp hover:bg-ds-surface-highest transition-colors text-sm text-ds-on-surface"
        >
          <.icon name="hero-photo" class="w-4 h-4 text-ds-on-surface-variant" />
          <span class="truncate" data-gallery-name>{gallery.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
