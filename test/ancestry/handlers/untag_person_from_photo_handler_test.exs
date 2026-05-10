defmodule Ancestry.Handlers.UntagPersonFromPhotoHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Audit.Log
  alias Ancestry.Bus
  alias Ancestry.Commands.UntagPersonFromPhoto
  alias Ancestry.Galleries.PhotoPerson
  alias Ancestry.Repo

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    person = insert(:person, organization: organization)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, photo: photo, person: person}
  end

  test "Bus.dispatch deletes the existing tag and audits",
       %{scope: scope, photo: photo, person: person} do
    Repo.insert!(%PhotoPerson{photo_id: photo.id, person_id: person.id, x: 0.5, y: 0.5})

    cmd = UntagPersonFromPhoto.new!(%{photo_id: photo.id, person_id: person.id})
    assert {:ok, :ok} = Bus.dispatch(scope, cmd)

    assert Repo.all(PhotoPerson) == []

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.UntagPersonFromPhoto"
    assert row.payload["arguments"]["photo_id"] == photo.id
    assert row.payload["arguments"]["person_id"] == person.id
  end

  test "Bus.dispatch is a no-op for non-existent tag (still audits)",
       %{scope: scope, photo: photo, person: person} do
    cmd = UntagPersonFromPhoto.new!(%{photo_id: photo.id, person_id: person.id})
    assert {:ok, :ok} = Bus.dispatch(scope, cmd)
    assert [_] = Repo.all(Log)
  end
end
