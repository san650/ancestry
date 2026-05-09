defmodule Ancestry.Commands.RemovePhotoFromGalleryTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.RemovePhotoFromGallery

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = RemovePhotoFromGallery.new(%{photo_id: 1})
    assert %RemovePhotoFromGallery{photo_id: 1} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = RemovePhotoFromGallery.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_id]
  end

  test "primary_step/0 == :photo" do
    assert RemovePhotoFromGallery.primary_step() == :photo
  end

  test "permission/0 == {:delete, Photo}" do
    assert RemovePhotoFromGallery.permission() == {:delete, Ancestry.Galleries.Photo}
  end
end
