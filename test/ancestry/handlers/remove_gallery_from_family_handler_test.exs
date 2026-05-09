defmodule Ancestry.Handlers.RemoveGalleryFromFamilyHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Audit.Log
  alias Ancestry.Bus
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Commands.RemoveGalleryFromFamily
  alias Ancestry.Galleries.{Gallery, Photo, PhotoPerson}
  alias Ancestry.Repo

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, gallery: gallery, family: family, organization: organization}
  end

  test "Bus.dispatch deletes the gallery and writes an audit row, cascading photos and tags",
       %{scope: scope, gallery: gallery, organization: organization} do
    person = insert(:person, organization: organization)
    photo = insert(:photo, gallery: gallery)

    photo_person =
      Repo.insert!(%PhotoPerson{photo_id: photo.id, person_id: person.id, x: 0.5, y: 0.5})

    photo_comment = insert(:photo_comment, photo: photo)

    cmd = RemoveGalleryFromFamily.new!(%{gallery_id: gallery.id})

    assert {:ok, %Gallery{id: id}} = Bus.dispatch(scope, cmd)
    assert id == gallery.id

    refute Repo.get(Gallery, gallery.id)
    refute Repo.get(Photo, photo.id)
    refute Repo.get(PhotoPerson, photo_person.id)
    refute Repo.get(PhotoComment, photo_comment.id)

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.RemoveGalleryFromFamily"
    assert row.payload["gallery_id"] == gallery.id
  end

  test "Bus.dispatch returns :not_found for missing gallery", %{scope: scope} do
    cmd = RemoveGalleryFromFamily.new!(%{gallery_id: -1})
    assert {:error, :not_found} = Bus.dispatch(scope, cmd)
    assert Repo.all(Log) == []
  end
end
