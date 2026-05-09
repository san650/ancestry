defmodule Ancestry.PermissionsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Authorization
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family
  alias Ancestry.People.Person
  alias Ancestry.Galleries.{Gallery, Photo}
  alias Ancestry.Organizations.Organization

  defp scope_for_role(role) do
    %Scope{account: %Account{role: role}}
  end

  describe "admin permissions" do
    setup do
      auth = Authorization.can(scope_for_role(:admin))
      %{auth: auth}
    end

    test "can read all resources", %{auth: auth} do
      assert Authorization.read?(auth, Account)
      assert Authorization.read?(auth, Organization)
      assert Authorization.read?(auth, Family)
      assert Authorization.read?(auth, Person)
      assert Authorization.read?(auth, Gallery)
      assert Authorization.read?(auth, Photo)
    end

    test "can create all resources", %{auth: auth} do
      assert Authorization.create?(auth, Account)
      assert Authorization.create?(auth, Organization)
      assert Authorization.create?(auth, Family)
      assert Authorization.create?(auth, Person)
      assert Authorization.create?(auth, Gallery)
      assert Authorization.create?(auth, Photo)
    end

    test "can update all resources", %{auth: auth} do
      assert Authorization.update?(auth, Account)
      assert Authorization.update?(auth, Organization)
      assert Authorization.update?(auth, Family)
      assert Authorization.update?(auth, Person)
      assert Authorization.update?(auth, Gallery)
      assert Authorization.update?(auth, Photo)
    end

    test "can delete all resources", %{auth: auth} do
      assert Authorization.delete?(auth, Account)
      assert Authorization.delete?(auth, Organization)
      assert Authorization.delete?(auth, Family)
      assert Authorization.delete?(auth, Person)
      assert Authorization.delete?(auth, Gallery)
      assert Authorization.delete?(auth, Photo)
    end
  end

  describe "editor permissions" do
    setup do
      auth = Authorization.can(scope_for_role(:editor))
      %{auth: auth}
    end

    test "can read content resources and organization", %{auth: auth} do
      assert Authorization.read?(auth, Organization)
      assert Authorization.read?(auth, Family)
      assert Authorization.read?(auth, Person)
      assert Authorization.read?(auth, Gallery)
      assert Authorization.read?(auth, Photo)
    end

    test "can create content resources", %{auth: auth} do
      assert Authorization.create?(auth, Family)
      assert Authorization.create?(auth, Person)
      assert Authorization.create?(auth, Gallery)
      assert Authorization.create?(auth, Photo)
    end

    test "can update content resources", %{auth: auth} do
      assert Authorization.update?(auth, Family)
      assert Authorization.update?(auth, Person)
      assert Authorization.update?(auth, Gallery)
      assert Authorization.update?(auth, Photo)
    end

    test "can delete content resources", %{auth: auth} do
      assert Authorization.delete?(auth, Family)
      assert Authorization.delete?(auth, Person)
      assert Authorization.delete?(auth, Gallery)
      assert Authorization.delete?(auth, Photo)
    end

    test "cannot access Account resources", %{auth: auth} do
      refute Authorization.read?(auth, Account)
      refute Authorization.create?(auth, Account)
      refute Authorization.update?(auth, Account)
      refute Authorization.delete?(auth, Account)
    end

    test "cannot write to Organization", %{auth: auth} do
      refute Authorization.create?(auth, Organization)
      refute Authorization.update?(auth, Organization)
      refute Authorization.delete?(auth, Organization)
    end
  end

  describe "viewer permissions" do
    setup do
      auth = Authorization.can(scope_for_role(:viewer))
      %{auth: auth}
    end

    test "can read content resources and organization", %{auth: auth} do
      assert Authorization.read?(auth, Organization)
      assert Authorization.read?(auth, Family)
      assert Authorization.read?(auth, Person)
      assert Authorization.read?(auth, Gallery)
      assert Authorization.read?(auth, Photo)
    end

    test "cannot create any resources", %{auth: auth} do
      refute Authorization.create?(auth, Account)
      refute Authorization.create?(auth, Organization)
      refute Authorization.create?(auth, Family)
      refute Authorization.create?(auth, Person)
      refute Authorization.create?(auth, Gallery)
      refute Authorization.create?(auth, Photo)
    end

    test "cannot update any resources", %{auth: auth} do
      refute Authorization.update?(auth, Account)
      refute Authorization.update?(auth, Organization)
      refute Authorization.update?(auth, Family)
      refute Authorization.update?(auth, Person)
      refute Authorization.update?(auth, Gallery)
      refute Authorization.update?(auth, Photo)
    end

    test "cannot delete any resources", %{auth: auth} do
      refute Authorization.delete?(auth, Account)
      refute Authorization.delete?(auth, Organization)
      refute Authorization.delete?(auth, Family)
      refute Authorization.delete?(auth, Person)
      refute Authorization.delete?(auth, Gallery)
      refute Authorization.delete?(auth, Photo)
    end

    test "cannot access Account resources", %{auth: auth} do
      refute Authorization.read?(auth, Account)
    end
  end

  describe "unauthenticated (nil scope)" do
    setup do
      auth = Authorization.can(%Scope{account: %Account{role: nil}})
      %{auth: auth}
    end

    test "cannot read any resources", %{auth: auth} do
      refute Authorization.read?(auth, Account)
      refute Authorization.read?(auth, Organization)
      refute Authorization.read?(auth, Family)
      refute Authorization.read?(auth, Person)
      refute Authorization.read?(auth, Gallery)
      refute Authorization.read?(auth, Photo)
    end

    test "cannot create any resources", %{auth: auth} do
      refute Authorization.create?(auth, Account)
      refute Authorization.create?(auth, Organization)
      refute Authorization.create?(auth, Family)
      refute Authorization.create?(auth, Person)
      refute Authorization.create?(auth, Gallery)
      refute Authorization.create?(auth, Photo)
    end

    test "cannot update any resources", %{auth: auth} do
      refute Authorization.update?(auth, Account)
      refute Authorization.update?(auth, Organization)
      refute Authorization.update?(auth, Family)
      refute Authorization.update?(auth, Person)
      refute Authorization.update?(auth, Gallery)
      refute Authorization.update?(auth, Photo)
    end

    test "cannot delete any resources", %{auth: auth} do
      refute Authorization.delete?(auth, Account)
      refute Authorization.delete?(auth, Organization)
      refute Authorization.delete?(auth, Family)
      refute Authorization.delete?(auth, Person)
      refute Authorization.delete?(auth, Gallery)
      refute Authorization.delete?(auth, Photo)
    end
  end

  describe "PhotoComment class-level rules" do
    defp scope(role) do
      %Scope{
        account: %Account{id: 1, role: role, email: "x@y.z"},
        organization: nil
      }
    end

    test "admin can update and delete PhotoComment at class level" do
      assert Authorization.can?(scope(:admin), :update, PhotoComment)
      assert Authorization.can?(scope(:admin), :delete, PhotoComment)
    end

    test "editor can update and delete PhotoComment at class level (record-level enforced in handler)" do
      assert Authorization.can?(scope(:editor), :update, PhotoComment)
      assert Authorization.can?(scope(:editor), :delete, PhotoComment)
    end

    test "viewer can create PhotoComment but not update/delete at class level" do
      assert Authorization.can?(scope(:viewer), :create, PhotoComment)
      refute Authorization.can?(scope(:viewer), :update, PhotoComment)
      refute Authorization.can?(scope(:viewer), :delete, PhotoComment)
    end
  end
end
