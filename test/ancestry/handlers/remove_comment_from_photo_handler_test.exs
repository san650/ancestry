defmodule Ancestry.Handlers.RemoveCommentFromPhotoHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus
  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.RemoveCommentFromPhoto
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Handlers.RemoveCommentFromPhotoHandler

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    owner = insert(:account, role: :editor)
    other = insert(:account, role: :editor)
    admin = insert(:account, role: :admin)

    comment = insert(:photo_comment, photo: photo, account: owner, text: "kill me")

    {:ok,
     organization: organization,
     photo: photo,
     comment: comment,
     owner_scope: %Ancestry.Identity.Scope{account: owner, organization: organization},
     other_scope: %Ancestry.Identity.Scope{account: other, organization: organization},
     admin_scope: %Ancestry.Identity.Scope{account: admin, organization: organization}}
  end

  test "handle/1 deletes the comment for the owner",
       %{owner_scope: scope, comment: comment} do
    cmd = RemoveCommentFromPhoto.new!(%{photo_comment_id: comment.id})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} = RemoveCommentFromPhotoHandler.handle(env)

    assert %PhotoComment{} = changes.comment
    assert is_nil(Ancestry.Repo.get(PhotoComment, comment.id))
    assert [{:broadcast, topic, {:comment_deleted, broadcast_comment}}] = changes.effects
    assert topic == "photo_comments:#{comment.photo_id}"
    assert %Ancestry.Identity.Account{} = broadcast_comment.account
  end

  test "Bus.dispatch returns :not_found for missing comment", %{owner_scope: scope} do
    cmd = RemoveCommentFromPhoto.new!(%{photo_comment_id: -1})
    assert {:error, :not_found} = Bus.dispatch(scope, cmd)
  end

  test "Bus.dispatch returns :unauthorized for a non-owner non-admin",
       %{other_scope: scope, comment: comment} do
    cmd = RemoveCommentFromPhoto.new!(%{photo_comment_id: comment.id})
    assert {:error, :unauthorized} = Bus.dispatch(scope, cmd)
    assert Ancestry.Repo.get(PhotoComment, comment.id)
  end

  test "Bus.dispatch broadcasts :comment_deleted to subscribers",
       %{owner_scope: scope, comment: comment, photo: photo} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
    cmd = RemoveCommentFromPhoto.new!(%{photo_comment_id: comment.id})

    assert {:ok, %PhotoComment{}} = Bus.dispatch(scope, cmd)
    assert_receive {:comment_deleted, %PhotoComment{id: id}}, 500
    assert id == comment.id
  end

  test "admin can delete any comment", %{admin_scope: scope, comment: comment} do
    cmd = RemoveCommentFromPhoto.new!(%{photo_comment_id: comment.id})
    assert {:ok, %PhotoComment{}} = Bus.dispatch(scope, cmd)
    assert is_nil(Ancestry.Repo.get(PhotoComment, comment.id))
  end
end
