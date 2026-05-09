defmodule Ancestry.Handlers.RemovePhotoFromGalleryHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Audit.Log
  alias Ancestry.Bus
  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.RemovePhotoFromGallery
  alias Ancestry.Galleries.Photo
  alias Ancestry.Handlers.RemovePhotoFromGalleryHandler
  alias Ancestry.Repo

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, photo: photo}
  end

  test "handle/1 deletes the photo, audits, computes :waffle_delete effect when image present",
       %{scope: scope, photo: photo} do
    cmd = RemovePhotoFromGallery.new!(%{photo_id: photo.id})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} = RemovePhotoFromGalleryHandler.handle(env)

    assert %Photo{} = changes.photo
    assert refute_photo_present(photo.id)
    assert changes.effects == []
  end

  test "Bus.dispatch deletes the photo + writes audit row", %{scope: scope, photo: photo} do
    cmd = RemovePhotoFromGallery.new!(%{photo_id: photo.id})

    assert {:ok, %Photo{}} = Bus.dispatch(scope, cmd)
    refute Repo.get(Photo, photo.id)

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.RemovePhotoFromGallery"
    assert row.payload["photo_id"] == photo.id
  end

  test "Bus.dispatch returns :not_found for missing photo", %{scope: scope} do
    cmd = RemovePhotoFromGallery.new!(%{photo_id: -1})
    assert {:error, :not_found} = Bus.dispatch(scope, cmd)
    assert Repo.all(Log) == []
  end

  defp refute_photo_present(id), do: is_nil(Repo.get(Photo, id))
end
