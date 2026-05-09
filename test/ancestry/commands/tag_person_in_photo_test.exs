defmodule Ancestry.Commands.TagPersonInPhotoTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.TagPersonInPhoto

  test "new/1 accepts coords" do
    assert {:ok, %TagPersonInPhoto{x: 0.5, y: 0.3}} =
             TagPersonInPhoto.new(%{photo_id: 1, person_id: 2, x: 0.5, y: 0.3})
  end

  test "new/1 accepts nil coords" do
    assert {:ok, %TagPersonInPhoto{x: nil, y: nil}} =
             TagPersonInPhoto.new(%{photo_id: 1, person_id: 2, x: nil, y: nil})
  end

  test "new/1 rejects mismatched coord state (only x set)" do
    assert {:error, %Ecto.Changeset{} = cs} =
             TagPersonInPhoto.new(%{photo_id: 1, person_id: 2, x: 0.5, y: nil})

    refute cs.valid?
  end

  test "new/1 rejects out-of-range x" do
    assert {:error, %Ecto.Changeset{} = cs} =
             TagPersonInPhoto.new(%{photo_id: 1, person_id: 2, x: 1.5, y: 0.5})

    refute cs.valid?
  end

  test "new/1 rejects out-of-range y" do
    assert {:error, %Ecto.Changeset{} = cs} =
             TagPersonInPhoto.new(%{photo_id: 1, person_id: 2, x: 0.5, y: -0.1})

    refute cs.valid?
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{}} = TagPersonInPhoto.new(%{})
  end

  test "primary_step/0 == :photo_person" do
    assert TagPersonInPhoto.primary_step() == :photo_person
  end

  test "permission/0 == {:update, Photo}" do
    assert TagPersonInPhoto.permission() == {:update, Ancestry.Galleries.Photo}
  end
end
