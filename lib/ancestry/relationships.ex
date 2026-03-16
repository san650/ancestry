defmodule Ancestry.Relationships do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.Relationships.Relationship

  def create_relationship(person_a, person_b, type, metadata_attrs \\ %{}) do
    attrs = %{
      person_a_id: person_a.id,
      person_b_id: person_b.id,
      type: type,
      metadata: Map.put(metadata_attrs, :__type__, type)
    }

    with :ok <- validate_parent_limit(person_b.id, type) do
      %Relationship{}
      |> Relationship.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_relationship(%Relationship{} = rel, attrs) do
    rel
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  def delete_relationship(%Relationship{} = rel) do
    Repo.delete(rel)
  end

  def convert_to_ex_partner(%Relationship{type: "partner"} = rel, divorce_attrs) do
    ex_metadata =
      %{
        __type__: "ex_partner",
        marriage_day: rel.metadata.marriage_day,
        marriage_month: rel.metadata.marriage_month,
        marriage_year: rel.metadata.marriage_year,
        marriage_location: rel.metadata.marriage_location
      }
      |> Map.merge(divorce_attrs)

    Repo.transaction(fn ->
      case Repo.delete(rel) do
        {:ok, _} ->
          %Relationship{}
          |> Relationship.changeset(%{
            person_a_id: rel.person_a_id,
            person_b_id: rel.person_b_id,
            type: "ex_partner",
            metadata: ex_metadata
          })
          |> Repo.insert!()

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def change_relationship(%Relationship{} = rel, attrs \\ %{}) do
    Relationship.changeset(rel, attrs)
  end

  defp validate_parent_limit(child_id, "parent") do
    count =
      Repo.aggregate(
        from(r in Relationship, where: r.person_b_id == ^child_id and r.type == "parent"),
        :count
      )

    if count >= 2, do: {:error, :max_parents_reached}, else: :ok
  end

  defp validate_parent_limit(_child_id, _type), do: :ok
end
