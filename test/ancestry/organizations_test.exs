defmodule Ancestry.OrganizationsTest do
  # async: false because the delete_organization/1 cascade tests touch the
  # filesystem (Waffle local storage) and assert on file presence/absence.
  use Ancestry.DataCase, async: false

  alias Ancestry.Organizations

  # Resolve a Waffle URL (which starts with "/" and excludes the storage_dir_prefix)
  # to its actual on-disk path under the configured storage prefix.
  defp staged_path(url) do
    prefix = Application.get_env(:waffle, :storage_dir_prefix)
    Path.join(prefix, String.trim_leading(url, "/"))
  end

  describe "delete_organization/1" do
    test "removes the org and cascades through families, galleries, photos" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      gallery = insert(:gallery, family: family)
      photo = insert(:photo, gallery: gallery, status: "processed")

      assert {:ok, _} = Organizations.delete_organization(org)

      refute Repo.get(Ancestry.Organizations.Organization, org.id)
      refute Repo.get(Ancestry.Families.Family, family.id)
      refute Repo.get(Ancestry.Galleries.Gallery, gallery.id)
      refute Repo.get(Ancestry.Galleries.Photo, photo.id)
    end

    test "cleans up Waffle photo files for every cascaded photo" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      gallery = insert(:gallery, family: family)

      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "task7_org_test.jpg", updated_at: nil}
        )

      file_url = Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
      file_path = staged_path(file_url)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "fake")
      on_exit(fn -> File.rm_rf(Path.dirname(file_path)) end)

      assert File.exists?(file_path)
      assert {:ok, _} = Organizations.delete_organization(org)
      refute File.exists?(file_path)
    end

    test "calls PersonPhoto.delete on every cascaded person's photo" do
      org = insert(:organization)

      person =
        insert(:person,
          organization: org,
          photo: %{file_name: "task7b_org_person.jpg", updated_at: nil},
          photo_status: "processed"
        )

      person_photo_path =
        Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)
        |> staged_path()

      File.mkdir_p!(Path.dirname(person_photo_path))
      File.write!(person_photo_path, "fake person photo")
      on_exit(fn -> File.rm_rf(Path.dirname(person_photo_path)) end)

      assert File.exists?(person_photo_path)
      assert {:ok, _} = Organizations.delete_organization(org)
      refute File.exists?(person_photo_path)
    end

    test "calls FamilyCover.delete on every cascaded family's cover" do
      org = insert(:organization)

      family =
        insert(:family,
          organization: org,
          cover: %{file_name: "task7b_org_cover.jpg", updated_at: nil},
          cover_status: "processed"
        )

      cover_path =
        Ancestry.Uploaders.FamilyCover.url({family.cover, family}, :cover)
        |> staged_path()

      File.mkdir_p!(Path.dirname(cover_path))
      File.write!(cover_path, "fake cover")
      on_exit(fn -> File.rm_rf(Path.dirname(cover_path)) end)

      assert File.exists?(cover_path)
      assert {:ok, _} = Organizations.delete_organization(org)
      refute File.exists?(cover_path)
    end
  end
end
