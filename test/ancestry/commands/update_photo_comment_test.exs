defmodule Ancestry.Commands.UpdatePhotoCommentTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.UpdatePhotoComment

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = UpdatePhotoComment.new(%{photo_comment_id: 7, text: "edit"})
    assert %UpdatePhotoComment{photo_comment_id: 7, text: "edit"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = UpdatePhotoComment.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_comment_id]
    assert {"can't be blank", _} = cs.errors[:text]
  end

  test "new/1 enforces text length max" do
    long = String.duplicate("a", 5001)
    assert {:error, cs} = UpdatePhotoComment.new(%{photo_comment_id: 1, text: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:text]
  end

  test "primary_step/0 == :comment" do
    assert UpdatePhotoComment.primary_step() == :comment
  end

  test "permission/0 == {:update, PhotoComment}" do
    assert UpdatePhotoComment.permission() == {:update, Ancestry.Comments.PhotoComment}
  end
end
