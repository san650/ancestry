defmodule Ancestry.Commands.AddGalleryToFamilyTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.AddGalleryToFamily

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = AddGalleryToFamily.new(%{family_id: 1, name: "Trip"})
    assert %AddGalleryToFamily{family_id: 1, name: "Trip"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = AddGalleryToFamily.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:family_id]
    assert {"can't be blank", _} = cs.errors[:name]
  end

  test "new/1 enforces name length" do
    long = String.duplicate("a", 256)
    assert {:error, cs} = AddGalleryToFamily.new(%{family_id: 1, name: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:name]
  end

  test "primary_step/0 == :gallery" do
    assert AddGalleryToFamily.primary_step() == :gallery
  end

  test "permission/0 == {:create, Gallery}" do
    assert AddGalleryToFamily.permission() == {:create, Ancestry.Galleries.Gallery}
  end
end
