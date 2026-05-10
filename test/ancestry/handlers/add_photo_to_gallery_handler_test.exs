defmodule Ancestry.Handlers.AddPhotoToGalleryHandlerTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  import Ancestry.Factory

  alias Ancestry.Audit.Log
  alias Ancestry.Bus
  alias Ancestry.Commands.AddPhotoToGallery
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, gallery: gallery}
  end

  test "Bus.dispatch creates photo + enqueues TransformAndStorePhoto + audits",
       %{scope: scope, gallery: gallery} do
    attrs = %{
      gallery_id: gallery.id,
      original_path: "/tmp/test_#{System.unique_integer([:positive])}.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      file_hash: "abc123"
    }

    {:ok, cmd} = AddPhotoToGallery.new(attrs)
    assert {:ok, %Photo{} = photo} = Bus.dispatch(scope, cmd)

    assert photo.gallery.id == gallery.id

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddPhotoToGallery"
    assert row.payload["arguments"]["file_hash"] == "abc123"
  end

  test "audit row metadata records the inserted photo's id",
       %{scope: scope, gallery: gallery} do
    attrs = %{
      gallery_id: gallery.id,
      original_path: "/tmp/test_#{System.unique_integer([:positive])}.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      file_hash: "abc123"
    }

    {:ok, cmd} = AddPhotoToGallery.new(attrs)
    assert {:ok, %Photo{} = photo} = Bus.dispatch(scope, cmd)

    assert [row] = Repo.all(Log)
    assert row.payload["metadata"] == %{"photo_id" => photo.id}
  end

  test "Bus.dispatch returns :validation for non-existent gallery", %{scope: scope} do
    cmd =
      AddPhotoToGallery.new!(%{
        gallery_id: -1,
        original_path: "/tmp/x.jpg",
        original_filename: "x.jpg",
        content_type: "image/jpeg",
        file_hash: "x"
      })

    assert {:error, :validation, %Ecto.Changeset{}} = Bus.dispatch(scope, cmd)
    assert Repo.all(Log) == []
  end
end
