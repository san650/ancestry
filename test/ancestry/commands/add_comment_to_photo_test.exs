defmodule Ancestry.Commands.AddCommentToPhotoTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.AddCommentToPhoto

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = AddCommentToPhoto.new(%{photo_id: 1, text: "hi"})
    assert %AddCommentToPhoto{photo_id: 1, text: "hi"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = AddCommentToPhoto.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_id]
    assert {"can't be blank", _} = cs.errors[:text]
  end

  test "new/1 enforces text length max" do
    long = String.duplicate("a", 5001)
    assert {:error, cs} = AddCommentToPhoto.new(%{photo_id: 1, text: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:text]
  end

  test "primary_step/0 == :comment" do
    assert AddCommentToPhoto.primary_step() == :comment
  end

  test "permission/0 == {:create, PhotoComment}" do
    assert AddCommentToPhoto.permission() == {:create, Ancestry.Comments.PhotoComment}
  end
end
