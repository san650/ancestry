defmodule Ancestry.Commands.RemoveCommentFromPhotoTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.RemoveCommentFromPhoto

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = RemoveCommentFromPhoto.new(%{photo_comment_id: 7})
    assert %RemoveCommentFromPhoto{photo_comment_id: 7} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = RemoveCommentFromPhoto.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_comment_id]
  end

  test "primary_step/0 == :comment" do
    assert RemoveCommentFromPhoto.primary_step() == :comment
  end

  test "permission/0 == {:delete, PhotoComment}" do
    assert RemoveCommentFromPhoto.permission() == {:delete, Ancestry.Comments.PhotoComment}
  end
end
