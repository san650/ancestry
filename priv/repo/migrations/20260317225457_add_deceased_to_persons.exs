defmodule Ancestry.Repo.Migrations.AddDeceasedToPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      add :deceased, :boolean, default: false
    end

    flush()

    execute("UPDATE persons SET deceased = true WHERE living = 'no'")

    flush()

    alter table(:persons) do
      modify :deceased, :boolean, null: false, default: false
    end
  end
end
