defmodule Ancestry.Repo.Migrations.AuditLogCorrelationIdsAndPayloadShape do
  use Ecto.Migration

  def up do
    alter table(:audit_log) do
      add :correlation_ids, {:array, :string}, null: false, default: []
    end

    execute "UPDATE audit_log SET correlation_ids = ARRAY[correlation_id]"

    drop index(:audit_log, [:correlation_id])

    alter table(:audit_log) do
      remove :correlation_id
    end

    create index(:audit_log, [:correlation_ids], using: :gin)

    execute """
    UPDATE audit_log
    SET payload = jsonb_build_object('arguments', payload, 'metadata', '{}'::jsonb)
    """
  end

  def down do
    execute "UPDATE audit_log SET payload = payload->'arguments'"

    drop index(:audit_log, [:correlation_ids])

    alter table(:audit_log) do
      add :correlation_id, :string
    end

    execute "UPDATE audit_log SET correlation_id = correlation_ids[1]"

    alter table(:audit_log) do
      modify :correlation_id, :string, null: false
    end

    alter table(:audit_log) do
      remove :correlation_ids
    end

    create index(:audit_log, [:correlation_id])
  end
end
