defmodule Ancestry.Commands.AddPhotoToGalleryTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.AddPhotoToGallery

  @valid %{
    gallery_id: 1,
    original_path: "/tmp/x.jpg",
    original_filename: "x.jpg",
    content_type: "image/jpeg",
    file_hash: "abc"
  }

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, %AddPhotoToGallery{file_hash: "abc"}} = AddPhotoToGallery.new(@valid)
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = AddPhotoToGallery.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:gallery_id]
    assert {"can't be blank", _} = cs.errors[:original_path]
    assert {"can't be blank", _} = cs.errors[:original_filename]
    assert {"can't be blank", _} = cs.errors[:content_type]
    assert {"can't be blank", _} = cs.errors[:file_hash]
  end

  test "primary_step/0 == :photo" do
    assert AddPhotoToGallery.primary_step() == :photo
  end

  test "permission/0 == {:create, Photo}" do
    assert AddPhotoToGallery.permission() == {:create, Ancestry.Galleries.Photo}
  end
end
