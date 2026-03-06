defmodule Family.GalleriesTest do
  use Family.DataCase, async: true

  alias Family.Galleries
  alias Family.Galleries.Gallery

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

  def gallery_fixture(attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery"})
      |> Galleries.create_gallery()

    gallery
  end
end
