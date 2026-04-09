defmodule Ancestry.FamiliesTest do
  # async: false because the new delete_family/1 cascade tests touch the
  # filesystem (Waffle local storage) and assert on file presence/absence.
  use Ancestry.DataCase, async: false

  alias Ancestry.Families
  alias Ancestry.Families.Family

  # Resolve a Waffle URL (which starts with "/" and excludes the storage_dir_prefix)
  # to its actual on-disk path under the configured storage prefix.
  defp staged_path(url) do
    prefix = Application.get_env(:waffle, :storage_dir_prefix)
    Path.join(prefix, String.trim_leading(url, "/"))
  end

  describe "families" do
    test "list_families/1 returns all families ordered by name" do
      {org, _} = org_fixture()
      f1 = family_fixture(org, %{name: "Beta"})
      f2 = family_fixture(org, %{name: "Alpha"})
      assert Families.list_families(org.id) == [f2, f1]
    end

    test "get_family!/1 returns the family with given id" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert Families.get_family!(family.id) == family
    end

    test "create_family/2 with valid data creates a family" do
      {org, _} = org_fixture()
      assert {:ok, %Family{} = family} = Families.create_family(org, %{name: "The Smiths"})
      assert family.name == "The Smiths"
    end

    test "create_family/2 with blank name returns error changeset" do
      {org, _} = org_fixture()
      assert {:error, %Ecto.Changeset{}} = Families.create_family(org, %{name: ""})
    end

    test "update_family/2 updates the family name" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert {:ok, %Family{} = updated} = Families.update_family(family, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_family/1 deletes the family" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert {:ok, %Family{}} = Families.delete_family(family)
      assert_raise Ecto.NoResultsError, fn -> Families.get_family!(family.id) end
    end

    test "change_family/2 returns a family changeset" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert %Ecto.Changeset{} = Families.change_family(family)
    end
  end

  describe "delete_family/1 cascade and file cleanup" do
    test "removes the family and cascades to galleries and photos" do
      family = insert(:family)
      gallery = insert(:gallery, family: family)
      photo = insert(:photo, gallery: gallery, status: "processed")

      assert {:ok, _} = Families.delete_family(family)

      refute Repo.get(Ancestry.Families.Family, family.id)
      refute Repo.get(Ancestry.Galleries.Gallery, gallery.id)
      refute Repo.get(Ancestry.Galleries.Photo, photo.id)
    end

    test "calls Waffle delete on each cascaded photo (closes the prod S3 leak)" do
      family = insert(:family)
      gallery = insert(:gallery, family: family)

      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "task7_test.jpg", updated_at: nil}
        )

      file_url = Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
      file_path = staged_path(file_url)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "fake")
      on_exit(fn -> File.rm_rf(Path.dirname(file_path)) end)

      assert File.exists?(file_path)
      assert {:ok, _} = Families.delete_family(family)
      refute File.exists?(file_path)
    end

    test "leaves files alone if the DB delete fails (atomicity)" do
      family = insert(:family)
      gallery = insert(:gallery, family: family)

      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "task7_atomicity.jpg", updated_at: nil}
        )

      file_url = Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
      file_path = staged_path(file_url)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "preserve me")
      on_exit(fn -> File.rm_rf(Path.dirname(file_path)) end)

      # Force a DB-level failure: pre-delete the family directly so the
      # struct passed to delete_family is stale.
      Repo.delete!(family)

      assert {:error, _} = Families.delete_family(family)
      assert File.exists?(file_path), "file must survive a failed DB delete"
    end

    test "calls FamilyCover.delete on the family cover when present" do
      family =
        insert(:family,
          cover: %{file_name: "task7b_cover.jpg", updated_at: nil},
          cover_status: "processed"
        )

      cover_path =
        Ancestry.Uploaders.FamilyCover.url({family.cover, family}, :cover)
        |> staged_path()

      File.mkdir_p!(Path.dirname(cover_path))
      File.write!(cover_path, "fake cover")
      on_exit(fn -> File.rm_rf(Path.dirname(cover_path)) end)

      assert File.exists?(cover_path)
      assert {:ok, _} = Families.delete_family(family)
      refute File.exists?(cover_path)
    end

    test "does NOT delete person photos when deleting a family (persons persist)" do
      family = insert(:family)

      person =
        insert(:person,
          organization: family.organization,
          photo: %{file_name: "task7b_person.jpg", updated_at: nil},
          photo_status: "processed"
        )

      {:ok, _} = Ancestry.People.add_to_family(person, family)

      person_photo_path =
        Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)
        |> staged_path()

      File.mkdir_p!(Path.dirname(person_photo_path))
      File.write!(person_photo_path, "preserve me")
      on_exit(fn -> File.rm_rf(Path.dirname(person_photo_path)) end)

      assert {:ok, _} = Families.delete_family(family)

      # Person and their photo file MUST survive
      assert Ancestry.People.get_person!(person.id)

      assert File.exists?(person_photo_path),
             "person photo must survive family delete"
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {org, org}
  end

  defp family_fixture(org, attrs \\ %{}) do
    {:ok, family} =
      Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
