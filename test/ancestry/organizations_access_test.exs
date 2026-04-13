defmodule Ancestry.OrganizationsAccessTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Organizations
  alias Ancestry.Organizations.AccountOrganization

  describe "list_organizations_for_account/1" do
    test "admin sees all organizations" do
      org1 = insert(:organization, name: "Alpha Org")
      org2 = insert(:organization, name: "Beta Org")

      admin = insert(:account) |> set_role(:admin)

      result = Organizations.list_organizations_for_account(admin)
      result_ids = Enum.map(result, & &1.id)

      assert org1.id in result_ids
      assert org2.id in result_ids
    end

    test "non-admin sees only associated organizations" do
      org1 = insert(:organization, name: "Alpha Org")
      org2 = insert(:organization, name: "Beta Org")
      _org3 = insert(:organization, name: "Gamma Org")

      editor = insert(:account) |> set_role(:editor)
      link_account_to_org(editor, org1)
      link_account_to_org(editor, org2)

      result = Organizations.list_organizations_for_account(editor)
      result_ids = Enum.map(result, & &1.id)

      assert org1.id in result_ids
      assert org2.id in result_ids
      assert length(result) == 2
    end

    test "non-admin with no associations sees empty list" do
      _org = insert(:organization)
      viewer = insert(:account) |> set_role(:viewer)

      assert Organizations.list_organizations_for_account(viewer) == []
    end
  end

  describe "account_has_org_access?/2" do
    test "admin has access to any organization" do
      org = insert(:organization)
      admin = insert(:account) |> set_role(:admin)

      assert Organizations.account_has_org_access?(admin, org.id)
    end

    test "non-admin with association has access" do
      org = insert(:organization)
      editor = insert(:account) |> set_role(:editor)
      link_account_to_org(editor, org)

      assert Organizations.account_has_org_access?(editor, org.id)
    end

    test "non-admin without association is denied" do
      org = insert(:organization)
      editor = insert(:account) |> set_role(:editor)

      refute Organizations.account_has_org_access?(editor, org.id)
    end
  end

  describe "create_organization/2 (with account)" do
    test "creates organization and auto-links creator" do
      account = insert(:account)

      assert {:ok, org} = Organizations.create_organization(%{name: "New Org"}, account)
      assert org.name == "New Org"

      # Verify the AccountOrganization join record was created
      assert Repo.get_by(AccountOrganization,
               account_id: account.id,
               organization_id: org.id
             )
    end

    test "returns error changeset when attrs are invalid" do
      account = insert(:account)

      assert {:error, changeset} = Organizations.create_organization(%{name: ""}, account)
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "get_organization/1" do
    test "returns organization when it exists" do
      org = insert(:organization)
      assert %Organizations.Organization{} = Organizations.get_organization(org.id)
    end

    test "returns nil when organization does not exist" do
      assert is_nil(Organizations.get_organization(0))
    end

    test "returns nil for non-id input" do
      assert is_nil(Organizations.get_organization(nil))
    end
  end

  # Helper to set the role on an account (factory doesn't support role yet)
  defp set_role(account, role) do
    Repo.update!(Ecto.Changeset.change(account, role: role))
  end

  # Helper to create an AccountOrganization link
  defp link_account_to_org(account, org) do
    Repo.insert!(%AccountOrganization{account_id: account.id, organization_id: org.id})
  end
end
