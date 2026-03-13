defmodule Ancestry.People do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.Person
  alias Ancestry.People.FamilyMember

  def list_people_for_family(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        order_by: [asc: p.surname, asc: p.given_name]
    )
  end

  def get_person!(id), do: Repo.get!(Person, id)

  def create_person(family, attrs) do
    Repo.transaction(fn ->
      case %Person{} |> Person.changeset(attrs) |> Repo.insert() do
        {:ok, person} ->
          %FamilyMember{family_id: family.id, person_id: person.id}
          |> FamilyMember.changeset(%{})
          |> Repo.insert!()

          person

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_person(%Person{} = person, attrs) do
    person
    |> Person.changeset(attrs)
    |> Repo.update()
  end

  def delete_person(%Person{} = person) do
    cleanup_person_files(person)
    Repo.delete(person)
  end

  def add_to_family(%Person{} = person, family) do
    %FamilyMember{family_id: family.id, person_id: person.id}
    |> FamilyMember.changeset(%{})
    |> Repo.insert()
  end

  def remove_from_family(%Person{} = person, family) do
    Repo.delete_all(
      from fm in FamilyMember,
        where: fm.family_id == ^family.id and fm.person_id == ^person.id
    )
    |> case do
      {1, _} -> {:ok, person}
      {0, _} -> {:error, :not_found}
    end
  end

  def search_people(query, exclude_family_id) do
    like = "%#{query}%"

    Repo.all(
      from p in Person,
        left_join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^exclude_family_id,
        where: is_nil(fm.id),
        where:
          ilike(p.given_name, ^like) or
            ilike(p.surname, ^like) or
            ilike(p.nickname, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20
    )
  end

  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  def update_photo_pending(%Person{} = person, original_path) do
    person
    |> Ecto.Changeset.change(%{photo_status: "pending"})
    |> Repo.update!()

    job_module = Module.concat(Ancestry.Workers, ProcessPersonPhotoJob)

    Oban.insert(
      job_module.new(%{
        person_id: person.id,
        original_path: original_path
      })
    )
  end

  def update_photo_processed(%Person{} = person, filename) do
    person
    |> Ecto.Changeset.change(%{
      photo: %{file_name: filename, updated_at: nil},
      photo_status: "processed"
    })
    |> Repo.update()
  end

  def update_photo_failed(%Person{} = person) do
    person
    |> Ecto.Changeset.change(%{photo_status: "failed"})
    |> Repo.update()
  end

  defp cleanup_person_files(person) do
    photo_dir = Path.join(["priv", "static", "uploads", "people", "#{person.id}"])
    File.rm_rf(photo_dir)
  end
end
