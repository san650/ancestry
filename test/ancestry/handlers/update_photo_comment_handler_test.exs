defmodule Ancestry.Handlers.UpdatePhotoCommentHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus
  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.UpdatePhotoComment
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Handlers.UpdatePhotoCommentHandler

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    owner = insert(:account, role: :editor)
    other = insert(:account, role: :editor)
    admin = insert(:account, role: :admin)

    comment = insert(:photo_comment, photo: photo, account: owner, text: "before")

    {:ok,
     organization: organization,
     photo: photo,
     comment: comment,
     owner_scope: %Ancestry.Identity.Scope{account: owner, organization: organization},
     other_scope: %Ancestry.Identity.Scope{account: other, organization: organization},
     admin_scope: %Ancestry.Identity.Scope{account: admin, organization: organization}}
  end

  test "handle/1 updates the comment when run by the owner",
       %{owner_scope: scope, comment: comment} do
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: comment.id, text: "after"})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} = UpdatePhotoCommentHandler.handle(env)

    assert %PhotoComment{text: "after"} = changes.updated_comment
    assert %PhotoComment{account: %Ancestry.Identity.Account{}} = changes.comment
    assert [{:broadcast, topic, {:comment_updated, _}}] = changes.effects
    assert topic == "photo_comments:#{comment.photo_id}"
  end

  test "Bus.dispatch returns :not_found for missing comment", %{owner_scope: scope} do
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: -1, text: "x"})
    assert {:error, :not_found} = Bus.dispatch(scope, cmd)
  end

  test "Bus.dispatch returns :unauthorized for a non-owner non-admin",
       %{other_scope: scope, comment: comment} do
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: comment.id, text: "hijack"})
    assert {:error, :unauthorized} = Bus.dispatch(scope, cmd)

    refreshed = Ancestry.Repo.get!(PhotoComment, comment.id)
    assert refreshed.text == "before"
  end

  test "Bus.dispatch broadcasts :comment_updated to subscribers",
       %{owner_scope: scope, comment: comment, photo: photo} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: comment.id, text: "broadcasted"})

    assert {:ok, %PhotoComment{text: "broadcasted"}} = Bus.dispatch(scope, cmd)
    assert_receive {:comment_updated, %PhotoComment{text: "broadcasted"}}, 500
  end

  test "Bus.dispatch records before/after text in audit metadata",
       %{owner_scope: scope, comment: comment} do
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: comment.id, text: "after"})
    assert {:ok, _} = Bus.dispatch(scope, cmd)

    [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.UpdatePhotoComment"
    assert row.payload["metadata"] == %{"before" => "before", "after" => "after"}
  end

  test "admin can update any comment", %{admin_scope: scope, comment: comment} do
    cmd = UpdatePhotoComment.new!(%{photo_comment_id: comment.id, text: "admin edit"})
    assert {:ok, %PhotoComment{text: "admin edit"}} = Bus.dispatch(scope, cmd)
  end
end
