defmodule Ancestry.Repo.Migrations.AddIsDefaultToFamilyMembers do
  use Ecto.Migration

  def change do
    alter table(:family_members) do
      add :is_default, :boolean, default: false, null: false
    end
  end
end
