defmodule Ancestry.Handlers.TagPersonInPhotoHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Audit.Log
  alias Ancestry.Bus
  alias Ancestry.Commands.TagPersonInPhoto
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

  test "Bus.dispatch creates a photo_person tag and audits",
       %{scope: scope, photo: photo, person: person} do
    cmd = TagPersonInPhoto.new!(%{photo_id: photo.id, person_id: person.id, x: 0.5, y: 0.4})

    assert {:ok, %PhotoPerson{x: 0.5, y: 0.4} = pp} = Bus.dispatch(scope, cmd)
    assert pp.photo_id == photo.id
    assert pp.person_id == person.id

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.TagPersonInPhoto"
    assert row.payload["photo_id"] == photo.id
    assert row.payload["person_id"] == person.id
  end

  test "Bus.dispatch upserts coordinates on existing tag",
       %{scope: scope, photo: photo, person: person} do
    cmd1 = TagPersonInPhoto.new!(%{photo_id: photo.id, person_id: person.id, x: nil, y: nil})
    assert {:ok, _} = Bus.dispatch(scope, cmd1)

    cmd2 = TagPersonInPhoto.new!(%{photo_id: photo.id, person_id: person.id, x: 0.7, y: 0.8})
    assert {:ok, %PhotoPerson{x: 0.7, y: 0.8}} = Bus.dispatch(scope, cmd2)

    assert length(Repo.all(PhotoPerson)) == 1
  end
end
