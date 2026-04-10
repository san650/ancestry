defmodule Ancestry.Memories.Vault do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memory_vaults" do
    field :name, :string
    field :memory_count, :integer, virtual: true, default: 0
    belongs_to :family, Ancestry.Families.Family
    has_many :memories, Ancestry.Memories.Memory, foreign_key: :memory_vault_id
    timestamps()
  end

  def changeset(vault, attrs) do
    vault
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:family_id)
  end
end
