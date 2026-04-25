defmodule Ancestry.Repo.Migrations.AddNameSearchToPersons do
  use Ecto.Migration
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.Person
  alias Ancestry.StringUtils

  def up do
    alter table(:persons) do
      add :name_search, :text
    end

    flush()

    # Backfill in Elixir to guarantee consistency with changeset logic
    Repo.all(Person)
    |> Enum.each(fn person ->
      name_search = compute_name_search(person)

      Repo.update_all(
        from(p in Person, where: p.id == ^person.id),
        set: [name_search: name_search]
      )
    end)
  end

  def down do
    alter table(:persons) do
      remove :name_search
    end
  end

  defp compute_name_search(person) do
    [
      person.given_name,
      person.surname,
      person.given_name_at_birth,
      person.surname_at_birth,
      person.nickname
    ]
    |> Kernel.++(person.alternate_names || [])
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> StringUtils.normalize()
  end
end
