defmodule Ancestry.Commands.UntagPersonFromPhotoTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.UntagPersonFromPhoto

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, %UntagPersonFromPhoto{photo_id: 1, person_id: 2}} =
             UntagPersonFromPhoto.new(%{photo_id: 1, person_id: 2})
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = UntagPersonFromPhoto.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_id]
    assert {"can't be blank", _} = cs.errors[:person_id]
  end

  test "primary_step/0 == :tag" do
    assert UntagPersonFromPhoto.primary_step() == :tag
  end

  test "permission/0 == {:update, Photo}" do
    assert UntagPersonFromPhoto.permission() == {:update, Ancestry.Galleries.Photo}
  end
end
