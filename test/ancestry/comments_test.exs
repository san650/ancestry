defmodule Ancestry.CommentsTest do
  use Ancestry.DataCase, async: true

  import Ancestry.Factory

  alias Ancestry.Comments

  describe "list_photo_comments/1" do
    test "returns comments ordered oldest first" do
      photo = insert(:photo)
      first = insert(:photo_comment, photo: photo, text: "First")
      second = insert(:photo_comment, photo: photo, text: "Second")

      comments = Comments.list_photo_comments(photo.id)
      assert [%{id: id1}, %{id: id2}] = comments
      assert id1 == first.id
      assert id2 == second.id
    end

    test "returns empty list when no comments" do
      photo = insert(:photo)
      assert [] == Comments.list_photo_comments(photo.id)
    end

    test "only returns comments for the given photo" do
      photo1 = insert(:photo)
      photo2 = insert(:photo)
      insert(:photo_comment, photo: photo1, text: "On photo 1")
      insert(:photo_comment, photo: photo2, text: "On photo 2")

      assert [comment] = Comments.list_photo_comments(photo1.id)
      assert comment.text == "On photo 1"
    end

    test "preloads accounts" do
      account = insert(:account)
      photo = insert(:photo)
      insert(:photo_comment, photo: photo, account: account, text: "Hello")

      [comment] = Comments.list_photo_comments(photo.id)
      assert %Ancestry.Identity.Account{} = comment.account
      assert comment.account.id == account.id
    end
  end

  describe "get_photo_comment!/1" do
    test "returns the comment" do
      comment = insert(:photo_comment, text: "Hello")

      fetched = Comments.get_photo_comment!(comment.id)
      assert fetched.id == comment.id
      assert fetched.text == "Hello"
    end
  end

  describe "cascade delete" do
    test "deleting a photo deletes its comments" do
      photo = insert(:photo)
      comment = insert(:photo_comment, photo: photo, text: "Cascade me")

      {:ok, _} = Ancestry.Galleries.delete_photo(photo)
      assert_raise Ecto.NoResultsError, fn -> Comments.get_photo_comment!(comment.id) end
    end
  end
end
