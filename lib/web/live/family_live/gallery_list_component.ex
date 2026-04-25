defmodule Web.FamilyLive.GalleryListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-cm-body font-semibold text-cm-text-muted uppercase tracking-wider">
          {gettext("Galleries")}
        </h3>
        <button
          id={"#{@id}-new-btn"}
          phx-click="open_new_gallery_modal"
          class="p-1 rounded text-cm-text-muted hover:text-cm-indigo hover:bg-cm-indigo/10 transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div id={"#{@id}-items"} class="space-y-1">
        <%= if @galleries == [] do %>
          <div class="text-sm text-cm-text-muted py-2">
            {gettext("No galleries yet.")}
          </div>
        <% end %>
        <.link
          :for={gallery <- @galleries}
          id={"#{@id}-#{gallery.id}"}
          navigate={~p"/org/#{@organization.id}/families/#{@family_id}/galleries/#{gallery.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-cm hover:bg-cm-surface transition-colors text-sm text-cm-black"
        >
          <.icon name="hero-photo" class="w-4 h-4 text-cm-text-muted" />
          <span class="truncate" data-gallery-name>{gallery.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
