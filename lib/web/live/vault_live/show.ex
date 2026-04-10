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
     |> assign(:confirm_delete_memory, nil)
     |> stream(:memories, memories)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # Delete vault

  @impl true
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

  # Delete memory

  def handle_event("request_delete_memory", %{"id" => id}, socket) do
    memory = Memories.get_memory!(id)
    {:noreply, assign(socket, :confirm_delete_memory, memory)}
  end

  def handle_event("cancel_delete_memory", _, socket) do
    {:noreply, assign(socket, :confirm_delete_memory, nil)}
  end

  def handle_event("confirm_delete_memory", _, socket) do
    memory = socket.assigns.confirm_delete_memory
    {:ok, _} = Memories.delete_memory(memory)

    {:noreply,
     socket
     |> assign(:confirm_delete_memory, nil)
     |> stream_delete(:memories, memory)}
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
