defmodule Ancestry.Repo.Migrations.AddLocaleToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :locale, :string, null: false, default: "en-US"
    end
  end
end
