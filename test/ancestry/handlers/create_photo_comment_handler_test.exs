defmodule Ancestry.Handlers.CreatePhotoCommentHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.CreatePhotoComment
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Handlers.CreatePhotoCommentHandler

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, photo: photo}
  end

  test "build_multi/1 inserts the comment, preloads :account, computes broadcast effect",
       %{scope: scope, photo: photo} do
    cmd = CreatePhotoComment.new!(%{photo_id: photo.id, text: "wow"})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} =
      env
      |> CreatePhotoCommentHandler.build_multi()
      |> Ancestry.Repo.transaction()

    assert %PhotoComment{text: "wow", account_id: id} = changes.photo_comment
    assert id == scope.account.id
    assert %PhotoComment{account: %Ancestry.Identity.Account{}} = changes.preloaded
    assert [{:broadcast, topic, {:comment_created, _}}] = changes.__effects__
    assert topic == "photo_comments:#{photo.id}"
  end

  test "Bus.dispatch wires the create command end-to-end", %{scope: scope, photo: photo} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
    {:ok, cmd} = CreatePhotoComment.new(%{photo_id: photo.id, text: "smoke"})

    assert {:ok, %PhotoComment{text: "smoke"} = c} = Ancestry.Bus.dispatch(scope, cmd)
    assert c.account.id == scope.account.id

    assert_receive {:comment_created, %PhotoComment{text: "smoke"}}, 500

    assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.CreatePhotoComment"
    assert row.payload == %{"photo_id" => photo.id, "text" => "smoke"}
  end
end
