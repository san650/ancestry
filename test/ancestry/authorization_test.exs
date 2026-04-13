defmodule Ancestry.AuthorizationTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Authorization
  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family

  defp scope_for(role) do
    %Scope{account: %Account{role: role}}
  end

  describe "can?/3" do
    test "returns true when scope has permission" do
      assert Authorization.can?(scope_for(:admin), :read, Family)
      assert Authorization.can?(scope_for(:editor), :create, Family)
    end

    test "returns false when scope lacks permission" do
      refute Authorization.can?(scope_for(:viewer), :create, Family)
      refute Authorization.can?(scope_for(:editor), :read, Account)
    end

    test "returns false for nil scope" do
      refute Authorization.can?(nil, :read, Family)
    end
  end
end
