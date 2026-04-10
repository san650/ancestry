defmodule Ancestry.Memories do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.Memories.Vault

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
end
