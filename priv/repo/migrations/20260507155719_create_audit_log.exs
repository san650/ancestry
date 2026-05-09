defmodule Ancestry.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def change do
    create table(:audit_log) do
      add :command_id, :string, null: false
      add :correlation_id, :string, null: false
      add :command_module, :string, null: false
      add :account_id, :bigint, null: false
      add :account_name, :string, null: true
      add :account_email, :string, null: false
      add :organization_id, :bigint, null: true
      add :organization_name, :string, null: true
      add :payload, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:audit_log, [:command_id])
    create index(:audit_log, [:correlation_id])
    create index(:audit_log, [:account_id, :inserted_at])
    create index(:audit_log, [:organization_id, :inserted_at])
    create index(:audit_log, [:command_module, :inserted_at])
  end
end
