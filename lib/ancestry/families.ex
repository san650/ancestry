defmodule Ancestry.Families do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Families.Family

  def list_families(org_id) do
    Repo.all(from f in Family, where: f.organization_id == ^org_id, order_by: [asc: f.name])
  end

  def get_family!(id), do: Repo.get!(Family, id)

  def create_family(%Ancestry.Organizations.Organization{} = org, attrs) do
    %Family{organization_id: org.id}
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

  def update_cover_pending(%Family{} = family, original_path) do
    family
    |> Ecto.Changeset.change(%{cover_status: "pending"})
    |> Repo.update!()

    Oban.insert(
      Ancestry.Workers.ProcessFamilyCoverJob.new(%{
        family_id: family.id,
        original_path: original_path
      })
    )
  end

  def update_cover_processed(%Family{} = family, filename) do
    family
    |> Ecto.Changeset.change(%{
      cover: %{file_name: filename, updated_at: nil},
      cover_status: "processed"
    })
    |> Repo.update()
  end

  def update_cover_failed(%Family{} = family) do
    family
    |> Ecto.Changeset.change(%{cover_status: "failed"})
    |> Repo.update()
  end

  defp cleanup_family_files(family) do
    cover_dir = Path.join(["priv", "static", "uploads", "families", "#{family.id}"])
    File.rm_rf(cover_dir)

    photos_dir = Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    File.rm_rf(photos_dir)
  end
end
