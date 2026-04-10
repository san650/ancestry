defmodule Ancestry.Memories.Memory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memories" do
    field :name, :string
    field :content, :string
    field :description, :string
    belongs_to :cover_photo, Ancestry.Galleries.Photo
    belongs_to :memory_vault, Ancestry.Memories.Vault
    belongs_to :account, Ancestry.Identity.Account, foreign_key: :inserted_by
    has_many :memory_mentions, Ancestry.Memories.MemoryMention
    has_many :mentioned_people, through: [:memory_mentions, :person]
    timestamps()
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:name, :content, :cover_photo_id, :memory_vault_id, :inserted_by])
    |> validate_required([:name, :memory_vault_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:memory_vault_id)
    |> foreign_key_constraint(:cover_photo_id)
    |> foreign_key_constraint(:inserted_by)
  end
end
