defmodule Web.VaultLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Memories
  alias Ancestry.Memories.Vault

  @impl true
  def mount(%{"family_id" => family_id, "vault_id" => vault_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    vault = Memories.get_vault!(vault_id)

    if vault.family_id != family.id do
      raise Ecto.NoResultsError, queryable: Vault
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "vault:#{vault.id}")
    end

    memories = Memories.list_memories(vault.id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:vault, vault)
     |> assign(:has_memories, memories != [])
     |> assign(:confirm_delete_vault, false)
     |> assign(:show_menu, false)
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_memories, false)
     |> stream(:memories, memories)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # Menu

  @impl true
  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
  end

  def handle_event("close_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, false)}
  end

  # Selection mode

  def handle_event("toggle_select_mode", _, socket) do
    {:noreply,
     socket
     |> assign(:selection_mode, !socket.assigns.selection_mode)
     |> assign(:selected_ids, MapSet.new())
     |> stream(:memories, Memories.list_memories(socket.assigns.vault.id), reset: true)}
  end

  def handle_event("memory_clicked", %{"id" => id}, socket) do
    if socket.assigns.selection_mode do
      handle_event("toggle_memory_select", %{"id" => id}, socket)
    else
      id = String.to_integer(id)

      {:noreply,
       push_navigate(socket,
         to:
           ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}/vaults/#{socket.assigns.vault.id}/memories/#{id}"
       )}
    end
  end

  def handle_event("toggle_memory_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    memory = Memories.get_memory!(id)

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> stream_insert(:memories, memory)}
  end

  # Bulk delete memories

  def handle_event("request_delete_memories", _, socket) do
    {:noreply, assign(socket, :confirm_delete_memories, true)}
  end

  def handle_event("cancel_delete_memories", _, socket) do
    {:noreply, assign(socket, :confirm_delete_memories, false)}
  end

  def handle_event("confirm_delete_memories", _, socket) do
    socket =
      Enum.reduce(MapSet.to_list(socket.assigns.selected_ids), socket, fn id, acc ->
        memory = Memories.get_memory!(id)
        {:ok, _} = Memories.delete_memory(memory)
        stream_delete(acc, :memories, memory)
      end)

    remaining = Memories.list_memories(socket.assigns.vault.id)

    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_memories, false)
     |> assign(:has_memories, remaining != [])
     |> stream(:memories, remaining, reset: true)}
  end

  # Delete vault

  def handle_event("request_delete_vault", _, socket) do
    {:noreply, assign(socket, :confirm_delete_vault, true)}
  end

  def handle_event("cancel_delete_vault", _, socket) do
    {:noreply, assign(socket, :confirm_delete_vault, false)}
  end

  def handle_event("confirm_delete_vault", _, socket) do
    {:ok, _} = Memories.delete_vault(socket.assigns.vault)

    {:noreply,
     push_navigate(socket,
       to:
         ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}"
     )}
  end

  # PubSub

  @impl true
  def handle_info({:memory_created, memory}, socket) do
    memory = Memories.get_memory!(memory.id)

    {:noreply,
     socket
     |> assign(:has_memories, true)
     |> stream_insert(:memories, memory, at: 0)}
  end

  def handle_info({:memory_updated, memory}, socket) do
    memory = Memories.get_memory!(memory.id)
    {:noreply, stream_insert(socket, :memories, memory)}
  end

  def handle_info({:memory_deleted, memory}, socket) do
    {:noreply, stream_delete(socket, :memories, memory)}
  end
end
