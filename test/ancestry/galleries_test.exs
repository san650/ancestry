defmodule Ancestry.GalleriesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Galleries.{Gallery, PhotoPerson}
  alias Ancestry.People
  alias Ancestry.Repo

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})
    %{family: family, org: org}
  end

  describe "galleries" do
    test "list_galleries/1 returns all galleries for a family ordered by inserted_at", %{
      family: family
    } do
      g1 = gallery_fixture(%{name: "Alpha", family_id: family.id})
      g2 = gallery_fixture(%{name: "Beta", family_id: family.id})
      assert Galleries.list_galleries(family.id) == [g1, g2]
    end

    test "get_gallery!/1 returns the gallery with given id", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert Galleries.get_gallery!(gallery.id) == gallery
    end

    test "change_gallery/2 returns a gallery changeset", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert %Ecto.Changeset{} = Galleries.change_gallery(gallery)
    end
  end

  describe "photos" do
    setup %{family: family} do
      gallery = insert(:gallery, name: "Test", family: family)
      %{gallery: gallery}
    end

    test "list_photos/1 returns photos ordered by inserted_at asc", %{gallery: gallery} do
      p1 = insert(:photo, gallery: gallery, original_filename: "a.jpg")
      p2 = insert(:photo, gallery: gallery, original_filename: "b.jpg")

      assert Enum.map(Galleries.list_photos(gallery.id), & &1.id) == [p1.id, p2.id]
    end

    test "update_photo_processed/2 sets status to processed", %{gallery: gallery} do
      photo = insert(:photo, gallery: gallery, status: "pending")

      assert {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
      assert updated.status == "processed"
    end

    test "update_photo_failed/1 sets status to failed", %{gallery: gallery} do
      photo = insert(:photo, gallery: gallery, status: "pending")

      assert {:ok, updated} = Galleries.update_photo_failed(photo)
      assert updated.status == "failed"
    end

    test "photo_exists_in_gallery?/2 returns true when hash exists in gallery", %{
      gallery: gallery
    } do
      insert(:photo, gallery: gallery, file_hash: "abc123")

      assert Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
    end

    test "photo_exists_in_gallery?/2 returns false when hash does not exist", %{gallery: gallery} do
      refute Galleries.photo_exists_in_gallery?(gallery.id, "nonexistent")
    end

    test "photo_exists_in_gallery?/2 returns false when same hash is in different gallery", %{
      gallery: gallery,
      family: family
    } do
      other_gallery = insert(:gallery, name: "Other", family: family)
      insert(:photo, gallery: other_gallery, file_hash: "abc123")

      refute Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
    end
  end

  describe "photo_people" do
    setup %{family: family, org: org} do
      gallery = insert(:gallery, name: "Test", family: family)
      photo = insert(:photo, gallery: gallery)

      {:ok, person} =
        Ancestry.People.create_person_without_family(org, %{given_name: "Alice", surname: "Smith"})

      %{gallery: gallery, photo: photo, person: person}
    end

    test "list_photo_people/1 returns tagged people with preloaded person", %{
      photo: photo,
      person: person,
      org: org
    } do
      {:ok, person2} =
        Ancestry.People.create_person_without_family(org, %{given_name: "Bob", surname: "Jones"})

      Repo.insert!(%PhotoPerson{photo_id: photo.id, person_id: person.id, x: 0.5, y: 0.3})
      Repo.insert!(%PhotoPerson{photo_id: photo.id, person_id: person2.id, x: 0.8, y: 0.6})

      result = Galleries.list_photo_people(photo.id)
      assert length(result) == 2
      assert Enum.all?(result, fn pp -> pp.person != nil end)
      assert hd(result).person.given_name == "Alice"
    end
  end

  describe "list_photos_for_person/1" do
    setup %{family: family} do
      gallery = insert(:gallery, name: "Test Gallery", family: family)
      {:ok, person} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})
      %{gallery: gallery, person: person}
    end

    test "returns processed photos where person is tagged, ordered by inserted_at desc", %{
      gallery: gallery,
      person: person
    } do
      photo1 =
        insert(:photo, gallery: gallery, status: "processed", original_filename: "test1.jpg")

      photo2 =
        insert(:photo, gallery: gallery, status: "processed", original_filename: "test2.jpg")

      # Pending photo — should not appear
      photo3 = insert(:photo, gallery: gallery, status: "pending", original_filename: "test3.jpg")

      Repo.insert!(%PhotoPerson{photo_id: photo1.id, person_id: person.id, x: 0.5, y: 0.5})
      Repo.insert!(%PhotoPerson{photo_id: photo2.id, person_id: person.id, x: 0.3, y: 0.3})
      Repo.insert!(%PhotoPerson{photo_id: photo3.id, person_id: person.id, x: 0.1, y: 0.1})

      result = Galleries.list_photos_for_person(person.id)

      assert length(result) == 2
      assert List.first(result).id == photo2.id
      assert List.last(result).id == photo1.id
      assert List.first(result).gallery != nil
    end

    test "returns empty list when person has no tagged photos", %{person: person} do
      assert Galleries.list_photos_for_person(person.id) == []
    end
  end

  def gallery_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Test Gallery"})

    %Gallery{}
    |> Gallery.changeset(attrs)
    |> Ancestry.Repo.insert!()
  end
end
