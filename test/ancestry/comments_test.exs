defmodule Ancestry.CommentsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Comments
  alias Ancestry.Comments.PhotoComment

  describe "create_photo_comment/3" do
    test "creates a comment with valid attrs" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      assert {:ok, %PhotoComment{} = comment} =
               Comments.create_photo_comment(photo.id, account.id, %{text: "Nice photo!"})

      assert comment.text == "Nice photo!"
      assert comment.photo_id == photo.id
      assert comment.account_id == account.id
    end

    test "returns comment with preloaded account" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      assert {:ok, %PhotoComment{} = comment} =
               Comments.create_photo_comment(photo.id, account.id, %{text: "Nice photo!"})

      assert %Ancestry.Identity.Account{} = comment.account
      assert comment.account.id == account.id
    end
  end

  describe "create_photo_comment/3 validations" do
    test "rejects empty text" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      assert {:error, changeset} =
               Comments.create_photo_comment(photo.id, account.id, %{text: ""})

      assert "can't be blank" in errors_on(changeset).text
    end

    test "rejects nil text" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      assert {:error, changeset} =
               Comments.create_photo_comment(photo.id, account.id, %{})

      assert "can't be blank" in errors_on(changeset).text
    end
  end

  describe "list_photo_comments/1" do
    test "returns comments ordered oldest first" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      {:ok, first} = Comments.create_photo_comment(photo.id, account.id, %{text: "First"})
      {:ok, second} = Comments.create_photo_comment(photo.id, account.id, %{text: "Second"})

      comments = Comments.list_photo_comments(photo.id)
      assert [%{id: id1}, %{id: id2}] = comments
      assert id1 == first.id
      assert id2 == second.id
    end

    test "returns empty list when no comments" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)

      assert [] == Comments.list_photo_comments(photo.id)
    end

    test "only returns comments for the given photo" do
      gallery = gallery_fixture()
      photo1 = photo_fixture(gallery)
      photo2 = photo_fixture(gallery)
      account = account_fixture()

      {:ok, _} = Comments.create_photo_comment(photo1.id, account.id, %{text: "On photo 1"})
      {:ok, _} = Comments.create_photo_comment(photo2.id, account.id, %{text: "On photo 2"})

      assert [comment] = Comments.list_photo_comments(photo1.id)
      assert comment.text == "On photo 1"
    end

    test "preloads accounts" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()

      {:ok, _} = Comments.create_photo_comment(photo.id, account.id, %{text: "Hello"})

      [comment] = Comments.list_photo_comments(photo.id)
      assert %Ancestry.Identity.Account{} = comment.account
      assert comment.account.id == account.id
    end
  end

  describe "get_photo_comment!/1" do
    test "returns the comment" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()
      {:ok, comment} = Comments.create_photo_comment(photo.id, account.id, %{text: "Hello"})

      fetched = Comments.get_photo_comment!(comment.id)
      assert fetched.id == comment.id
      assert fetched.text == "Hello"
    end
  end

  describe "update_photo_comment/2" do
    test "updates text" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()
      {:ok, comment} = Comments.create_photo_comment(photo.id, account.id, %{text: "Original"})

      assert {:ok, updated} = Comments.update_photo_comment(comment, %{text: "Edited"})
      assert updated.text == "Edited"
    end

    test "rejects empty text on update" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()
      {:ok, comment} = Comments.create_photo_comment(photo.id, account.id, %{text: "Original"})

      assert {:error, changeset} = Comments.update_photo_comment(comment, %{text: ""})
      assert "can't be blank" in errors_on(changeset).text
    end
  end

  describe "delete_photo_comment/1" do
    test "deletes the comment" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()
      {:ok, comment} = Comments.create_photo_comment(photo.id, account.id, %{text: "Delete me"})

      assert {:ok, _} = Comments.delete_photo_comment(comment)
      assert_raise Ecto.NoResultsError, fn -> Comments.get_photo_comment!(comment.id) end
    end
  end

  describe "cascade delete" do
    test "deleting a photo deletes its comments" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)
      account = account_fixture()
      {:ok, comment} = Comments.create_photo_comment(photo.id, account.id, %{text: "Cascade me"})

      {:ok, _} = Ancestry.Galleries.delete_photo(photo)
      assert_raise Ecto.NoResultsError, fn -> Comments.get_photo_comment!(comment.id) end
    end
  end

  defp account_fixture do
    {:ok, account} =
      %Ancestry.Identity.Account{}
      |> Ecto.Changeset.change(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("valid_password123"),
        confirmed_at: DateTime.utc_now(:second),
        name: "Test User"
      })
      |> Ancestry.Repo.insert()

    account
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
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end

  defp photo_fixture(gallery) do
    tmp_dir = Path.join(System.tmp_dir!(), "comment_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
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
