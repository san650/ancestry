defmodule Ancestry.GalleriesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery

  describe "galleries" do
    test "list_galleries/0 returns all galleries ordered by inserted_at" do
      g1 = gallery_fixture(%{name: "Alpha"})
      g2 = gallery_fixture(%{name: "Beta"})
      assert Galleries.list_galleries() == [g1, g2]
    end

    test "get_gallery!/1 returns the gallery with given id" do
      gallery = gallery_fixture()
      assert Galleries.get_gallery!(gallery.id) == gallery
    end

    test "create_gallery/1 with valid data creates a gallery" do
      assert {:ok, %Gallery{} = gallery} = Galleries.create_gallery(%{name: "Vacation 2025"})
      assert gallery.name == "Vacation 2025"
    end

    test "create_gallery/1 with blank name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Galleries.create_gallery(%{name: ""})
    end

    test "delete_gallery/1 deletes the gallery" do
      gallery = gallery_fixture()
      assert {:ok, %Gallery{}} = Galleries.delete_gallery(gallery)
      assert_raise Ecto.NoResultsError, fn -> Galleries.get_gallery!(gallery.id) end
    end

    test "change_gallery/2 returns a gallery changeset" do
      gallery = gallery_fixture()
      assert %Ecto.Changeset{} = Galleries.change_gallery(gallery)
    end
  end

  describe "photos" do
    setup do
      {:ok, gallery} = Galleries.create_gallery(%{name: "Test"})
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
  end

  def gallery_fixture(attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery"})
      |> Galleries.create_gallery()

    gallery
  end
end
