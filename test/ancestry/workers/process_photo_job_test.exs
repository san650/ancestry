defmodule Ancestry.Workers.ProcessPhotoJobTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.Workers.ProcessPhotoJob
  alias Ancestry.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test"})

    tmp_dir = Path.join(System.tmp_dir!(), "photo_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    original_path = Path.join(tmp_dir, "photo.jpg")
    File.cp!(Path.join(__DIR__, "../../fixtures/test_image.jpg"), original_path)

    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: original_path,
        original_filename: "test_image.jpg",
        content_type: "image/jpeg"
      })

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{photo: photo, gallery: gallery}
  end

  test "performs job: processes photo and broadcasts :photo_processed", %{
    photo: photo,
    gallery: gallery
  } do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "gallery:#{gallery.id}")

    assert :ok = perform_job(ProcessPhotoJob, %{photo_id: photo.id})

    updated = Galleries.get_photo!(photo.id)
    assert updated.status == "processed"
    assert updated.image != nil

    assert_receive {:photo_processed, ^updated}
  end

  test "marks photo as failed and broadcasts :photo_failed when original_path is missing", %{
    photo: photo,
    gallery: gallery
  } do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "gallery:#{gallery.id}")

    # Delete the file so the job will fail to process it
    File.rm!(photo.original_path)

    assert {:error, _reason} = ProcessPhotoJob.perform(%Oban.Job{args: %{"photo_id" => photo.id}})

    updated = Galleries.get_photo!(photo.id)
    assert updated.status == "failed"

    assert_receive {:photo_failed, _}
  end
end
