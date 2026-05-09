defmodule Ancestry.Handlers.AddGalleryToFamilyHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus
  alias Ancestry.Commands.AddGalleryToFamily
  alias Ancestry.Galleries.Gallery

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, family: family}
  end

  test "Bus.dispatch creates a gallery and writes an audit row", %{scope: scope, family: family} do
    {:ok, cmd} = AddGalleryToFamily.new(%{family_id: family.id, name: "Trip"})

    assert {:ok, %Gallery{name: "Trip"} = gallery} = Bus.dispatch(scope, cmd)
    assert gallery.family_id == family.id

    assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.AddGalleryToFamily"
    assert row.payload["name"] == "Trip"
    assert row.payload["family_id"] == family.id
  end

  test "Bus.dispatch returns :validation for invalid family_id", %{scope: scope} do
    cmd = AddGalleryToFamily.new!(%{family_id: -1, name: "Trip"})

    assert {:error, :validation, %Ecto.Changeset{}} = Bus.dispatch(scope, cmd)
    assert Ancestry.Repo.all(Ancestry.Audit.Log) == []
  end
end
