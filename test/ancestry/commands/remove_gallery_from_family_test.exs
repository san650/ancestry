defmodule Ancestry.Commands.RemoveGalleryFromFamilyTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.RemoveGalleryFromFamily

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = RemoveGalleryFromFamily.new(%{gallery_id: 1})
    assert %RemoveGalleryFromFamily{gallery_id: 1} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = RemoveGalleryFromFamily.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:gallery_id]
  end

  test "primary_step/0 == :gallery" do
    assert RemoveGalleryFromFamily.primary_step() == :gallery
  end

  test "permission/0 == {:delete, Gallery}" do
    assert RemoveGalleryFromFamily.permission() == {:delete, Ancestry.Galleries.Gallery}
  end
end
