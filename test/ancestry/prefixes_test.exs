defmodule Ancestry.PrefixesTest do
  use ExUnit.Case, async: true

  alias Ancestry.Prefixes

  describe "for!/1" do
    test "returns the registered prefix" do
      assert Prefixes.for!(:command) == "cmd"
      assert Prefixes.for!(:request) == "req"
    end

    test "raises on unknown kind" do
      assert_raise FunctionClauseError, fn -> Prefixes.for!(:unknown) end
    end
  end

  describe "generate/1" do
    test "produces <prefix>-<uuid>" do
      id = Prefixes.generate(:command)
      assert <<"cmd-", uuid::binary-size(36)>> = id
      assert {:ok, _} = Ecto.UUID.cast(uuid)
    end

    test "successive calls produce unique ids" do
      refute Prefixes.generate(:request) == Prefixes.generate(:request)
    end
  end

  describe "parse!/1" do
    test "splits a registered id" do
      id = Prefixes.generate(:command)
      assert {"cmd", _uuid} = Prefixes.parse!(id)
    end

    test "raises on unknown prefix" do
      assert_raise ArgumentError, fn -> Prefixes.parse!("xyz-foo") end
    end
  end

  describe "known_kinds/0" do
    test "lists all registered kinds" do
      kinds = Prefixes.known_kinds()
      assert :command in kinds
      assert :request in kinds
    end
  end
end
