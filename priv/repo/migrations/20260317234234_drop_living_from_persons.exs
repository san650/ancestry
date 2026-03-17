defmodule Ancestry.Repo.Migrations.DropLivingFromPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      remove :living, :text, default: "yes", null: false
    end
  end
end
