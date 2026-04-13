defmodule Ancestry.Identity.AccountTest do
  use Ancestry.DataCase, async: true
  alias Ancestry.Identity.Account

  describe "admin_changeset/3 for creation" do
    test "valid attrs produce a valid changeset" do
      changeset =
        Account.admin_changeset(%Account{}, %{
          email: "new@example.com",
          name: "Test User",
          role: :editor,
          password: "password123456"
        })

      assert changeset.valid?
      assert get_change(changeset, :confirmed_at)
      assert get_change(changeset, :hashed_password)
      refute get_change(changeset, :password)
    end

    test "requires email" do
      changeset = Account.admin_changeset(%Account{}, %{password: "password123456"})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires password on creation" do
      changeset = Account.admin_changeset(%Account{}, %{email: "a@b.com"})
      assert "can't be blank" in errors_on(changeset).password
    end

    test "validates email format" do
      changeset =
        Account.admin_changeset(%Account{}, %{email: "invalid", password: "password123456"})

      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "validates password length" do
      changeset = Account.admin_changeset(%Account{}, %{email: "a@b.com", password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "validates role via Ecto.Enum" do
      changeset =
        Account.admin_changeset(%Account{}, %{
          email: "a@b.com",
          password: "password123456",
          role: :superadmin
        })

      refute changeset.valid?
    end

    test "validates password confirmation" do
      changeset =
        Account.admin_changeset(%Account{}, %{
          email: "a@b.com",
          password: "password123456",
          password_confirmation: "different123456"
        })

      assert "does not match password" in errors_on(changeset).password_confirmation
    end
  end

  describe "admin_changeset/3 for editing" do
    test "skips password when empty string" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}

      changeset =
        Account.admin_changeset(account, %{name: "Updated", password: ""}, mode: :edit)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Updated"
      refute get_change(changeset, :hashed_password)
    end

    test "skips password when absent" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}
      changeset = Account.admin_changeset(account, %{name: "Updated"}, mode: :edit)
      assert changeset.valid?
      refute get_change(changeset, :hashed_password)
    end

    test "updates password when provided on edit" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}
      changeset = Account.admin_changeset(account, %{password: "newpassword123"}, mode: :edit)
      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
    end
  end
end
