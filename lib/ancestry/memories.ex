defmodule Ancestry.Memories do
  import Ecto.Query

  alias Ecto.Multi
  alias Ancestry.Repo
  alias Ancestry.Memories.Vault
  alias Ancestry.Memories.Memory
  alias Ancestry.Memories.MemoryMention
  alias Ancestry.Memories.ContentParser
  alias Ancestry.People.Person

  # --- Vaults ---

  def list_vaults(family_id) do
    Repo.all(
      from v in Vault,
        where: v.family_id == ^family_id,
        left_join: m in assoc(v, :memories),
        group_by: v.id,
        select_merge: %{memory_count: count(m.id)},
        order_by: [desc: v.inserted_at, desc: v.id]
    )
  end

  def get_vault!(id) do
    Repo.get!(Vault, id)
  end

  def create_vault(family, attrs) do
    %Vault{family_id: family.id}
    |> Vault.changeset(attrs)
    |> Repo.insert()
  end

  def update_vault(%Vault{} = vault, attrs) do
    vault
    |> Vault.changeset(attrs)
    |> Repo.update()
  end

  def delete_vault(%Vault{} = vault) do
    Repo.delete(vault)
  end

  def change_vault(%Vault{} = vault, attrs \\ %{}) do
    Vault.changeset(vault, attrs)
  end

  # --- Memories ---

  def list_memories(vault_id) do
    Repo.all(
      from m in Memory,
        where: m.memory_vault_id == ^vault_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        preload: [:cover_photo]
    )
  end

  def get_memory!(id) do
    Repo.get!(Memory, id)
    |> Repo.preload([:cover_photo, memory_mentions: :person])
  end

  def create_memory(%Vault{} = vault, account, attrs) do
    vault = Repo.preload(vault, :family)
    org_id = vault.family.organization_id
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    content = Map.get(attrs, "content", "")
    {description, person_ids, _photo_ids} = ContentParser.parse(content)
    valid_person_ids = filter_org_person_ids(person_ids, org_id)

    Multi.new()
    |> Multi.insert(:memory, fn _ ->
      %Memory{memory_vault_id: vault.id, inserted_by: account.id}
      |> Memory.changeset(attrs)
      |> Ecto.Changeset.put_change(:description, description)
    end)
    |> Multi.insert_all(:mentions, MemoryMention, fn %{memory: memory} ->
      Enum.map(valid_person_ids, fn pid ->
        %{memory_id: memory.id, person_id: pid}
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{memory: memory}} ->
        Phoenix.PubSub.broadcast(Ancestry.PubSub, "vault:#{vault.id}", {:memory_created, memory})
        {:ok, memory}

      {:error, _failed_operation, failed_value, _changes} ->
        {:error, failed_value}
    end
  end

  def update_memory(%Memory{} = memory, attrs) do
    memory = Repo.preload(memory, memory_vault: :family)
    org_id = memory.memory_vault.family.organization_id
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    content = Map.get(attrs, "content", memory.content || "")
    {description, person_ids, _photo_ids} = ContentParser.parse(content)
    valid_person_ids = filter_org_person_ids(person_ids, org_id)

    Multi.new()
    |> Multi.update(:memory, fn _ ->
      memory
      |> Memory.changeset(attrs)
      |> Ecto.Changeset.put_change(:description, description)
    end)
    |> Multi.delete_all(:delete_mentions, fn _ ->
      from mm in MemoryMention, where: mm.memory_id == ^memory.id
    end)
    |> Multi.insert_all(:mentions, MemoryMention, fn _ ->
      Enum.map(valid_person_ids, fn pid ->
        %{memory_id: memory.id, person_id: pid}
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{memory: memory}} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "vault:#{memory.memory_vault_id}",
          {:memory_updated, memory}
        )

        {:ok, memory}

      {:error, _failed_operation, failed_value, _changes} ->
        {:error, failed_value}
    end
  end

  def delete_memory(%Memory{} = memory) do
    case Repo.delete(memory) do
      {:ok, memory} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "vault:#{memory.memory_vault_id}",
          {:memory_deleted, memory}
        )

        {:ok, memory}

      error ->
        error
    end
  end

  def change_memory(%Memory{} = memory, attrs \\ %{}) do
    Memory.changeset(memory, attrs)
  end

  defp filter_org_person_ids([], _org_id), do: []

  defp filter_org_person_ids(person_ids, org_id) do
    Repo.all(
      from p in Person,
        where: p.id in ^person_ids and p.organization_id == ^org_id,
        select: p.id
    )
  end
end
