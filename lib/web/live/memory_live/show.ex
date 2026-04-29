defmodule Web.MemoryLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Memories
  alias Ancestry.Memories.ContentRenderer

  @impl true
  def mount(
        %{"family_id" => family_id, "vault_id" => vault_id, "memory_id" => memory_id},
        _session,
        socket
      ) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    vault = Memories.get_vault!(vault_id)

    if vault.family_id != family.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Vault
    end

    memory = Memories.get_memory!(memory_id)

    if memory.memory_vault_id != vault.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Memory
    end

    # Build people map for ContentRenderer
    people_map =
      memory.memory_mentions
      |> Enum.map(fn mention -> {mention.person_id, mention.person} end)
      |> Map.new()

    org_id = socket.assigns.current_scope.organization.id
    rendered_content = ContentRenderer.render(memory.content, people_map, org_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:vault, vault)
     |> assign(:memory, memory)
     |> assign(:rendered_content, rendered_content)
     |> assign(:show_menu, false)
     |> assign(:confirm_delete, false)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
  end

  def handle_event("close_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, false)}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Memories.delete_memory(socket.assigns.memory)

    {:noreply,
     push_navigate(socket,
       to:
         ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}/vaults/#{socket.assigns.vault.id}"
     )}
  end
end
