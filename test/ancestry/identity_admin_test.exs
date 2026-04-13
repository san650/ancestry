defmodule Ancestry.Identity.AdminTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Identity
  alias Ancestry.Identity.{Account, AccountToken}

  import Ancestry.IdentityFixtures

  describe "list_accounts/0" do
    test "returns all accounts sorted by email" do
      account_b = insert(:account, email: "bravo@example.com")
      account_a = insert(:account, email: "alpha@example.com")
      account_c = insert(:account, email: "charlie@example.com")

      result = Identity.list_accounts()
      emails = Enum.map(result, & &1.email)

      assert emails == ["alpha@example.com", "bravo@example.com", "charlie@example.com"]
      result_ids = Enum.map(result, & &1.id)
      assert result_ids == [account_a.id, account_b.id, account_c.id]
    end
  end

  describe "create_admin_account/2" do
    test "creates account with role and confirmed_at" do
      attrs = %{
        email: "admin@example.com",
        name: "Admin User",
        role: :admin,
        password: "valid_password123"
      }

      assert {:ok, account} = Identity.create_admin_account(attrs, [])
      assert account.email == "admin@example.com"
      assert account.name == "Admin User"
      assert account.role == :admin
      assert account.confirmed_at != nil
    end

    test "creates account with organization associations" do
      org1 = insert(:organization)
      org2 = insert(:organization)

      attrs = %{
        email: "admin@example.com",
        name: "Admin User",
        role: :admin,
        password: "valid_password123"
      }

      assert {:ok, account} = Identity.create_admin_account(attrs, [org1.id, org2.id])

      account = Repo.preload(account, :organizations)
      org_ids = Enum.map(account.organizations, & &1.id) |> Enum.sort()
      assert org_ids == Enum.sort([org1.id, org2.id])
    end

    test "returns error for invalid attrs" do
      attrs = %{email: "not-valid", password: "short"}

      assert {:error, changeset} = Identity.create_admin_account(attrs, [])
      assert %{email: _} = errors_on(changeset)
    end
  end

  describe "update_admin_account/3" do
    setup do
      account = insert(:account)
      account = Repo.update!(Ecto.Changeset.change(account, role: :admin))
      account = Repo.get!(Account, account.id)
      %{account: account}
    end

    test "updates account fields", %{account: account} do
      assert {:ok, updated} =
               Identity.update_admin_account(account, %{name: "New Name"}, account)

      assert updated.name == "New Name"
    end

    test "prevents self-role-change", %{account: account} do
      assert {:error, :cannot_change_own_role} =
               Identity.update_admin_account(account, %{role: :viewer}, account)
    end

    test "allows self-edit without role change", %{account: account} do
      assert {:ok, updated} =
               Identity.update_admin_account(account, %{name: "Updated", role: :admin}, account)

      assert updated.name == "Updated"
    end

    test "allows admin to change another account's role", %{account: admin} do
      target = insert(:account)
      target = Repo.update!(Ecto.Changeset.change(target, role: :editor))
      target = Repo.get!(Account, target.id)

      assert {:ok, updated} =
               Identity.update_admin_account(target, %{role: :viewer}, admin)

      assert updated.role == :viewer
    end
  end

  describe "deactivate_account/2" do
    test "deactivates account and deletes tokens" do
      admin = insert(:account)
      admin = Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      target = insert(:account)
      target = Repo.update!(Ecto.Changeset.change(target, role: :editor))
      target = Repo.get!(Account, target.id)

      _token = Identity.generate_account_session_token(target)

      assert {:ok, deactivated} = Identity.deactivate_account(target, admin)
      assert deactivated.deactivated_at != nil
      assert deactivated.deactivated_by == admin.id

      # Tokens should be deleted
      assert Repo.all(from(t in AccountToken, where: t.account_id == ^target.id)) == []
    end

    test "prevents self-deactivation" do
      admin = insert(:account)
      admin = Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      assert {:error, :cannot_deactivate_self} = Identity.deactivate_account(admin, admin)
    end

    test "prevents deactivating the last active admin" do
      # Create 2 admins
      admin1 = insert(:account)
      admin1 = Repo.update!(Ecto.Changeset.change(admin1, role: :admin))
      admin1 = Repo.get!(Account, admin1.id)

      admin2 = insert(:account)
      admin2 = Repo.update!(Ecto.Changeset.change(admin2, role: :admin))
      admin2 = Repo.get!(Account, admin2.id)

      # Deactivate one admin (leaving 1 active admin) - this should succeed
      assert {:ok, _} = Identity.deactivate_account(admin2, admin1)

      # Now admin1 is the sole active admin.
      # Trying to deactivate a non-admin target from the sole admin should succeed.
      editor = insert(:account)
      editor = Repo.update!(Ecto.Changeset.change(editor, role: :editor))
      editor = Repo.get!(Account, editor.id)

      assert {:ok, _} = Identity.deactivate_account(editor, admin1)

      # But trying to deactivate admin1 (the last active admin) should fail.
      # We need another non-deactivated account to attempt this (can't self-deactivate).
      # Create a new admin to attempt the deactivation.
      admin3 = insert(:account)
      admin3 = Repo.update!(Ecto.Changeset.change(admin3, role: :admin))
      admin3 = Repo.get!(Account, admin3.id)

      # Now there are 2 active admins again (admin1 + admin3).
      # Deactivate admin3 first, leaving admin1 as the only admin.
      assert {:ok, _} = Identity.deactivate_account(admin3, admin1)

      # admin1 is now the last admin. admin2 is deactivated (admin).
      # We need someone to try deactivating admin1. Let's use a fresh admin.
      admin4 = insert(:account)
      admin4 = Repo.update!(Ecto.Changeset.change(admin4, role: :admin))
      admin4 = Repo.get!(Account, admin4.id)

      # Currently active admins: admin1, admin4 (2 active admins)
      # Deactivating admin1 would leave admin4 as sole admin -- that's allowed.
      assert {:ok, _} = Identity.deactivate_account(admin1, admin4)

      # Now admin4 is the last active admin. Try to deactivate admin4 from another.
      # But admin4 can't self-deactivate, and there's no other active admin.
      # Let's create a non-admin to try deactivating admin4... but the function is called by
      # the performer. Let's create another admin specifically for this scenario.
      admin5 = insert(:account)
      admin5 = Repo.update!(Ecto.Changeset.change(admin5, role: :admin))
      admin5 = Repo.get!(Account, admin5.id)

      # Active admins: admin4, admin5. Deactivate admin5 leaving admin4 as last.
      assert {:ok, _} = Identity.deactivate_account(admin5, admin4)

      # Now admin4 is truly the last active admin. admin5 is deactivated but has admin role.
      # Create yet another admin to perform the deactivation attempt.
      admin6 = insert(:account)
      admin6 = Repo.update!(Ecto.Changeset.change(admin6, role: :admin))
      admin6 = Repo.get!(Account, admin6.id)

      # Active admins: admin4, admin6.
      # Deactivate admin6, leaving admin4 as last active admin.
      assert {:ok, _} = Identity.deactivate_account(admin6, admin4)

      # Now: only admin4 is active admin. Try having a new performer deactivate admin4.
      performer = insert(:account)
      performer = Repo.update!(Ecto.Changeset.change(performer, role: :admin))
      performer = Repo.get!(Account, performer.id)

      # Active admins: admin4, performer (2).
      # Trying to deactivate admin4 would leave performer (1 active admin) -- allowed.
      # Instead let's test the real scenario: when deactivation would leave 0 active admins.
      # That happens when both the target AND the result of the deactivation would leave 0.
      # Actually, the check is: if the target is an admin, count of active admins must be > 1.
      # So we need: only 1 active admin, and that admin is the target.

      # Reset: deactivate performer leaving admin4 as the only active admin.
      # But performer is the one doing it, so that's self-deactivation. Use admin4 to deactivate performer.
      assert {:ok, _} = Identity.deactivate_account(performer, admin4)

      # admin4 is the last active admin. Create a non-admin performer to call the function.
      # The function should check if deactivating an admin-role target would leave 0 admins.
      non_admin_performer = insert(:account)

      non_admin_performer =
        Repo.update!(Ecto.Changeset.change(non_admin_performer, role: :editor))

      non_admin_performer = Repo.get!(Account, non_admin_performer.id)

      assert {:error, :last_admin} = Identity.deactivate_account(admin4, non_admin_performer)
    end

    test "allows deactivating non-admin when only one admin remains" do
      admin = insert(:account)
      admin = Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      editor = insert(:account)
      editor = Repo.update!(Ecto.Changeset.change(editor, role: :editor))
      editor = Repo.get!(Account, editor.id)

      # Only one admin, but target is not an admin, so this should succeed
      assert {:ok, _} = Identity.deactivate_account(editor, admin)
    end
  end

  describe "reactivate_account/1" do
    test "clears deactivation fields" do
      admin = insert(:account)
      admin = Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      target = insert(:account)
      target = Repo.update!(Ecto.Changeset.change(target, role: :editor))
      target = Repo.get!(Account, target.id)

      {:ok, deactivated} = Identity.deactivate_account(target, admin)
      assert deactivated.deactivated_at != nil

      assert {:ok, reactivated} = Identity.reactivate_account(deactivated)
      assert reactivated.deactivated_at == nil
      assert reactivated.deactivated_by == nil
    end
  end

  describe "login guards for deactivated accounts" do
    test "get_account_by_email_and_password returns nil for deactivated account" do
      account = insert(:account) |> set_password()

      # Deactivate the account
      admin = insert(:account)
      admin = Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      # Directly deactivate via changeset to avoid needing a different admin
      Repo.update!(
        Ecto.Changeset.change(account,
          deactivated_at: DateTime.utc_now(:second),
          deactivated_by: admin.id
        )
      )

      refute Identity.get_account_by_email_and_password(account.email, valid_account_password())
    end

    test "get_account_by_session_token returns nil for deactivated account" do
      account = insert(:account)
      token = Identity.generate_account_session_token(account)

      # Deactivate the account
      Repo.update!(Ecto.Changeset.change(account, deactivated_at: DateTime.utc_now(:second)))

      refute Identity.get_account_by_session_token(token)
    end
  end
end
