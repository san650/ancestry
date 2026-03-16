defmodule Ancestry.CommentsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Comments
  alias Ancestry.Comments.PhotoComment

  describe "create_photo_comment/1" do
    test "creates a comment with valid attrs" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)

      assert {:ok, %PhotoComment{} = comment} =
               Comments.create_photo_comment(%{text: "Nice photo!", photo_id: photo.id})

      assert comment.text == "Nice photo!"
      assert comment.photo_id == photo.id
    end
  end

  defp gallery_fixture(attrs \\ %{}) do
    family = family_fixture()

    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery", family_id: family.id})
      |> Ancestry.Galleries.create_gallery()

    gallery
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end

  defp photo_fixture(gallery) do
    tmp_dir = Path.join(System.tmp_dir!(), "comment_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    dest = Path.join(tmp_dir, "photo.jpg")
    File.cp!("test/fixtures/test_image.jpg", dest)

    {:ok, photo} =
      Ancestry.Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: dest,
        original_filename: "photo.jpg",
        content_type: "image/jpeg"
      })

    photo
  end
end
