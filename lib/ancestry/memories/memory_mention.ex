defmodule Ancestry.Memories.MemoryMention do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memory_mentions" do
    belongs_to :memory, Ancestry.Memories.Memory
    belongs_to :person, Ancestry.People.Person
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:memory_id, :person_id])
    |> validate_required([:memory_id, :person_id])
    |> foreign_key_constraint(:memory_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:memory_id, :person_id])
  end
end
