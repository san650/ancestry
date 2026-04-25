defmodule Web.FamilyLive.VaultListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-cm-body font-semibold text-cm-text-muted uppercase tracking-wider">
          {gettext("Memory Vaults")}
        </h3>
        <button
          id={"#{@id}-new-btn"}
          phx-click="open_new_vault_modal"
          class="p-1 rounded text-cm-text-muted hover:text-cm-indigo hover:bg-cm-indigo/10 transition-colors"
          {test_id("vault-new-btn")}
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div id={"#{@id}-items"} class="space-y-1">
        <%= if @vaults == [] do %>
          <div class="text-sm text-cm-text-muted py-2" {test_id("vaults-empty")}>
            {gettext("No memory vaults yet.")}
          </div>
        <% end %>
        <.link
          :for={vault <- @vaults}
          id={"#{@id}-#{vault.id}"}
          navigate={~p"/org/#{@organization.id}/families/#{@family_id}/vaults/#{vault.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-cm hover:bg-cm-surface transition-colors text-sm text-cm-black"
          {test_id("vault-item-#{vault.id}")}
        >
          <.icon name="hero-book-open" class="w-4 h-4 text-cm-text-muted" />
          <span class="truncate flex-1">{vault.name}</span>
          <span class="text-xs text-cm-text-muted">{vault.memory_count}</span>
        </.link>
      </div>
    </div>
    """
  end
end
