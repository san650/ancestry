defmodule Ancestry.GalleriesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery
  alias Ancestry.People

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

    test "create_gallery/1 with valid data creates a gallery", %{family: family} do
      assert {:ok, %Gallery{} = gallery} =
               Galleries.create_gallery(%{name: "Vacation 2025", family_id: family.id})

      assert gallery.name == "Vacation 2025"
    end

    test "create_gallery/1 with blank name returns error changeset", %{family: family} do
      assert {:error, %Ecto.Changeset{}} =
               Galleries.create_gallery(%{name: "", family_id: family.id})
    end

    test "delete_gallery/1 deletes the gallery", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert {:ok, %Gallery{}} = Galleries.delete_gallery(gallery)
      assert_raise Ecto.NoResultsError, fn -> Galleries.get_gallery!(gallery.id) end
    end

    test "change_gallery/2 returns a gallery changeset", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert %Ecto.Changeset{} = Galleries.change_gallery(gallery)
    end
  end

  describe "photos" do
    setup %{family: family} do
      {:ok, gallery} = Galleries.create_gallery(%{name: "Test", family_id: family.id})
      %{gallery: gallery}
    end

    test "list_photos/1 returns photos ordered by inserted_at asc", %{gallery: gallery} do
      {:ok, p1} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/a.jpg",
          original_filename: "a.jpg",
          content_type: "image/jpeg"
        })

      {:ok, p2} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/b.jpg",
          original_filename: "b.jpg",
          content_type: "image/jpeg"
        })

      assert Enum.map(Galleries.list_photos(gallery.id), & &1.id) == [p1.id, p2.id]
    end

    test "create_photo/1 creates a pending photo", %{gallery: gallery} do
      assert {:ok, photo} =
               Galleries.create_photo(%{
                 gallery_id: gallery.id,
                 original_path: "/tmp/test.jpg",
                 original_filename: "test.jpg",
                 content_type: "image/jpeg"
               })

      assert photo.status == "pending"
      assert photo.gallery_id == gallery.id
    end

    test "delete_photo/1 deletes the photo", %{gallery: gallery} do
      {:ok, photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg"
        })

      assert {:ok, _} = Galleries.delete_photo(photo)
      assert Galleries.list_photos(gallery.id) == []
    end

    test "update_photo_processed/2 sets status to processed", %{gallery: gallery} do
      {:ok, photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg"
        })

      assert {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
      assert updated.status == "processed"
    end

    test "update_photo_failed/1 sets status to failed", %{gallery: gallery} do
      {:ok, photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg"
        })

      assert {:ok, updated} = Galleries.update_photo_failed(photo)
      assert updated.status == "failed"
    end

    test "photo_exists_in_gallery?/2 returns true when hash exists in gallery", %{
      gallery: gallery
    } do
      {:ok, _photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg",
          file_hash: "abc123"
        })

      assert Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
    end

    test "photo_exists_in_gallery?/2 returns false when hash does not exist", %{gallery: gallery} do
      refute Galleries.photo_exists_in_gallery?(gallery.id, "nonexistent")
    end

    test "photo_exists_in_gallery?/2 returns false when same hash is in different gallery", %{
      gallery: gallery,
      family: family
    } do
      {:ok, other_gallery} = Galleries.create_gallery(%{name: "Other", family_id: family.id})

      {:ok, _photo} =
        Galleries.create_photo(%{
          gallery_id: other_gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg",
          file_hash: "abc123"
        })

      refute Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
    end
  end

  describe "photo_people" do
    setup %{family: family, org: org} do
      {:ok, gallery} = Galleries.create_gallery(%{name: "Test", family_id: family.id})

      {:ok, photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test.jpg",
          original_filename: "test.jpg",
          content_type: "image/jpeg"
        })

      {:ok, person} =
        Ancestry.People.create_person_without_family(org, %{given_name: "Alice", surname: "Smith"})

      %{gallery: gallery, photo: photo, person: person}
    end

    test "tag_person_in_photo/4 creates a photo_person record", %{photo: photo, person: person} do
      assert {:ok, photo_person} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
      assert photo_person.photo_id == photo.id
      assert photo_person.person_id == person.id
      assert photo_person.x == 0.5
      assert photo_person.y == 0.3
    end

    test "tag_person_in_photo/4 rejects duplicate tag", %{photo: photo, person: person} do
      assert {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
      assert {:error, changeset} = Galleries.tag_person_in_photo(photo.id, person.id, 0.2, 0.8)
      assert "has already been taken" in errors_on(changeset).photo_id
    end

    test "tag_person_in_photo/4 validates coordinate bounds", %{photo: photo, person: person} do
      assert {:error, changeset} = Galleries.tag_person_in_photo(photo.id, person.id, 1.5, -0.1)
      assert errors_on(changeset).x
      assert errors_on(changeset).y
    end

    test "untag_person_from_photo/2 removes the tag", %{photo: photo, person: person} do
      {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
      assert :ok = Galleries.untag_person_from_photo(photo.id, person.id)
      assert Galleries.list_photo_people(photo.id) == []
    end

    test "untag_person_from_photo/2 is a no-op when not tagged", %{photo: photo, person: person} do
      assert :ok = Galleries.untag_person_from_photo(photo.id, person.id)
    end

    test "list_photo_people/1 returns tagged people with preloaded person", %{
      photo: photo,
      person: person,
      org: org
    } do
      {:ok, person2} =
        Ancestry.People.create_person_without_family(org, %{given_name: "Bob", surname: "Jones"})

      {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
      {:ok, _} = Galleries.tag_person_in_photo(photo.id, person2.id, 0.8, 0.6)

      result = Galleries.list_photo_people(photo.id)
      assert length(result) == 2
      assert Enum.all?(result, fn pp -> pp.person != nil end)
      assert hd(result).person.given_name == "Alice"
    end
  end

  describe "list_photos_for_person/1" do
    setup %{family: family} do
      {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})
      {:ok, person} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})
      %{gallery: gallery, person: person}
    end

    test "returns processed photos where person is tagged, ordered by inserted_at desc", %{
      gallery: gallery,
      person: person
    } do
      {:ok, photo1} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test1.jpg",
          original_filename: "test1.jpg",
          content_type: "image/jpeg"
        })

      {:ok, photo1} = Galleries.update_photo_processed(photo1, "test1.jpg")

      {:ok, photo2} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test2.jpg",
          original_filename: "test2.jpg",
          content_type: "image/jpeg"
        })

      {:ok, photo2} = Galleries.update_photo_processed(photo2, "test2.jpg")

      # Pending photo — should not appear
      {:ok, photo3} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          original_path: "/tmp/test3.jpg",
          original_filename: "test3.jpg",
          content_type: "image/jpeg"
        })

      {:ok, _} = Galleries.tag_person_in_photo(photo1.id, person.id, 0.5, 0.5)
      {:ok, _} = Galleries.tag_person_in_photo(photo2.id, person.id, 0.3, 0.3)
      {:ok, _} = Galleries.tag_person_in_photo(photo3.id, person.id, 0.1, 0.1)

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
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery"})
      |> Galleries.create_gallery()

    gallery
  end
end
