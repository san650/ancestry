defmodule Ancestry.Repo.Migrations.AddOrganizationIdToFamiliesAndPersons do
  use Ecto.Migration

  def up do
    # Create a default organization for existing data
    execute """
    INSERT INTO organizations (name, inserted_at, updated_at)
    VALUES ('Default Organization', NOW(), NOW())
    """

    # Add organization_id to families (nullable first for backfill)
    alter table(:families) do
      add :organization_id, references(:organizations, on_delete: :delete_all)
    end

    # Backfill families
    execute """
    UPDATE families SET organization_id = (SELECT id FROM organizations LIMIT 1)
    """

    # Make NOT NULL
    alter table(:families) do
      modify :organization_id, :bigint, null: false
    end

    create index(:families, [:organization_id])

    # Add organization_id to persons (nullable first for backfill)
    alter table(:persons) do
      add :organization_id, references(:organizations, on_delete: :delete_all)
    end

    # Backfill persons
    execute """
    UPDATE persons SET organization_id = (SELECT id FROM organizations LIMIT 1)
    """

    # Make NOT NULL
    alter table(:persons) do
      modify :organization_id, :bigint, null: false
    end

    create index(:persons, [:organization_id])
  end

  def down do
    alter table(:persons) do
      remove :organization_id
    end

    alter table(:families) do
      remove :organization_id
    end

    execute "DELETE FROM organizations"
  end
end
