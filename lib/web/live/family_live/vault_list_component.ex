defmodule Web.FamilyLive.VaultListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-ds-body font-semibold text-ds-on-surface-variant uppercase tracking-wider">
          {gettext("Memory Vaults")}
        </h3>
        <button
          id={"#{@id}-new-btn"}
          phx-click="open_new_vault_modal"
          class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
          {test_id("vault-new-btn")}
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div id={"#{@id}-items"} class="space-y-1">
        <%= if @vaults == [] do %>
          <div class="text-sm text-ds-on-surface-variant py-2" {test_id("vaults-empty")}>
            {gettext("No memory vaults yet.")}
          </div>
        <% end %>
        <.link
          :for={vault <- @vaults}
          id={"#{@id}-#{vault.id}"}
          navigate={~p"/org/#{@organization.id}/families/#{@family_id}/vaults/#{vault.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-ds-sharp hover:bg-ds-surface-highest transition-colors text-sm text-ds-on-surface"
          {test_id("vault-item-#{vault.id}")}
        >
          <.icon name="hero-book-open" class="w-4 h-4 text-ds-on-surface-variant" />
          <span class="truncate flex-1">{vault.name}</span>
          <span class="text-xs text-ds-on-surface-variant">{vault.memory_count}</span>
        </.link>
      </div>
    </div>
    """
  end
end
