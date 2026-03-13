defmodule Ancestry.Repo.Migrations.CreatePersons do
  use Ecto.Migration

  def change do
    create table(:persons) do
      add :given_name, :text
      add :surname, :text
      add :given_name_at_birth, :text
      add :surname_at_birth, :text
      add :nickname, :text
      add :title, :text
      add :suffix, :text
      add :alternate_names, {:array, :text}, default: []
      add :birth_day, :integer
      add :birth_month, :integer
      add :birth_year, :integer
      add :death_day, :integer
      add :death_month, :integer
      add :death_year, :integer
      add :living, :text, default: "yes", null: false
      add :gender, :text
      add :photo, :text
      add :photo_status, :text

      timestamps()
    end
  end
end
