defmodule Ancestry.Repo.Migrations.AddAccountIdToPhotoComments do
  use Ecto.Migration

  def change do
    alter table(:photo_comments) do
      add :account_id, references(:accounts, on_delete: :nilify_all)
    end

    create index(:photo_comments, [:account_id])
  end
end
