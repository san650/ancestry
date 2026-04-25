defmodule Ancestry.Repo.Migrations.AddKindToPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      add :kind, :string, null: false, default: "family_member"
    end
  end
end
