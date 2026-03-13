defmodule Ancestry.Families do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Families.Family

  def list_families do
    Repo.all(from f in Family, order_by: [asc: f.name])
  end

  def get_family!(id), do: Repo.get!(Family, id)

  def create_family(attrs \\ %{}) do
    %Family{}
    |> Family.changeset(attrs)
    |> Repo.insert()
  end

  def update_family(%Family{} = family, attrs) do
    family
    |> Family.changeset(attrs)
    |> Repo.update()
  end

  def delete_family(%Family{} = family) do
    cleanup_family_files(family)
    Repo.delete(family)
  end

  def change_family(%Family{} = family, attrs \\ %{}) do
    Family.changeset(family, attrs)
  end

  defp cleanup_family_files(family) do
    cover_dir = Path.join(["priv", "static", "uploads", "families", "#{family.id}"])
    File.rm_rf(cover_dir)

    photos_dir = Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    File.rm_rf(photos_dir)
  end
end
