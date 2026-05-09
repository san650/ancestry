defmodule Ancestry.Commands.DeletePhotoCommentTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.DeletePhotoComment

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = DeletePhotoComment.new(%{photo_comment_id: 7})
    assert %DeletePhotoComment{photo_comment_id: 7} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = DeletePhotoComment.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_comment_id]
  end

  test "primary_step/0 == :photo_comment" do
    assert DeletePhotoComment.primary_step() == :photo_comment
  end

  test "permission/0 == {:delete, PhotoComment}" do
    assert DeletePhotoComment.permission() == {:delete, Ancestry.Comments.PhotoComment}
  end
end
