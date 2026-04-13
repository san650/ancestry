defmodule Ancestry.Repo.Migrations.AddAccountManagement do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :name, :string
      add :role, :string, null: false, default: "editor"
      add :deactivated_at, :utc_datetime
      add :deactivated_by, references(:accounts, on_delete: :nilify_all)
      add :avatar, :string
      add :avatar_status, :string
    end

    execute "UPDATE accounts SET role = 'admin'", "SELECT 1"

    create table(:account_organizations) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_organizations, [:account_id, :organization_id])
    create index(:account_organizations, [:organization_id])
  end
end
