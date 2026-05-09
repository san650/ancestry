defmodule Ancestry.Commands.CreatePhotoCommentTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.CreatePhotoComment

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = CreatePhotoComment.new(%{photo_id: 1, text: "hi"})
    assert %CreatePhotoComment{photo_id: 1, text: "hi"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = CreatePhotoComment.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_id]
    assert {"can't be blank", _} = cs.errors[:text]
  end

  test "new/1 enforces text length max" do
    long = String.duplicate("a", 5001)
    assert {:error, cs} = CreatePhotoComment.new(%{photo_id: 1, text: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:text]
  end

  test "primary_step/0 == :preloaded" do
    assert CreatePhotoComment.primary_step() == :preloaded
  end

  test "permission/0 == {:create, PhotoComment}" do
    assert CreatePhotoComment.permission() == {:create, Ancestry.Comments.PhotoComment}
  end
end
