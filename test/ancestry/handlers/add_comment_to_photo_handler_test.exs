defmodule Ancestry.Handlers.AddCommentToPhotoHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.AddCommentToPhoto
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Handlers.AddCommentToPhotoHandler

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, photo: photo}
  end

  test "handle/1 inserts the comment, preloads :account, computes broadcast effect",
       %{scope: scope, photo: photo} do
    cmd = AddCommentToPhoto.new!(%{photo_id: photo.id, text: "wow"})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} = AddCommentToPhotoHandler.handle(env)

    assert %PhotoComment{text: "wow", account_id: id} = changes.inserted_comment
    assert id == scope.account.id
    assert %PhotoComment{account: %Ancestry.Identity.Account{}} = changes.comment
    assert [{:broadcast, topic, {:comment_created, _}}] = changes.effects
    assert topic == "photo_comments:#{photo.id}"
  end

  test "Bus.dispatch wires the create command end-to-end", %{scope: scope, photo: photo} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
    {:ok, cmd} = AddCommentToPhoto.new(%{photo_id: photo.id, text: "smoke"})

    assert {:ok, %PhotoComment{text: "smoke"} = c} = Ancestry.Bus.dispatch(scope, cmd)
    assert c.account.id == scope.account.id

    assert_receive {:comment_created, %PhotoComment{text: "smoke"}}, 500

    assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.AddCommentToPhoto"
    assert row.payload["arguments"] == %{"photo_id" => photo.id, "text" => "smoke"}
    assert row.payload["metadata"] == %{"text" => "smoke"}
  end
end
