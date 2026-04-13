defmodule Ancestry.Organizations.AccountOrganization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_organizations" do
    belongs_to :account, Ancestry.Identity.Account
    belongs_to :organization, Ancestry.Organizations.Organization
    timestamps(type: :utc_datetime)
  end

  def changeset(account_organization, attrs) do
    account_organization
    |> cast(attrs, [:account_id, :organization_id])
    |> validate_required([:account_id, :organization_id])
    |> unique_constraint([:account_id, :organization_id])
  end
end
