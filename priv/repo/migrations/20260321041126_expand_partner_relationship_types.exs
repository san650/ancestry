defmodule Ancestry.Repo.Migrations.ExpandPartnerRelationshipTypes do
  use Ecto.Migration

  def up do
    execute """
    UPDATE relationships
    SET type = 'relationship',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"relationship"')
    WHERE type = 'partner'
    """

    execute """
    UPDATE relationships
    SET type = 'separated',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"separated"')
    WHERE type = 'ex_partner'
    """
  end

  def down do
    execute """
    UPDATE relationships
    SET type = 'partner',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"partner"')
    WHERE type IN ('married', 'relationship')
    """

    execute """
    UPDATE relationships
    SET type = 'ex_partner',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"ex_partner"')
    WHERE type IN ('divorced', 'separated')
    """
  end
end
