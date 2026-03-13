defmodule Ancestry.Workers.ProcessPersonPhotoJobTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.People
  alias Ancestry.Workers.ProcessPersonPhotoJob

  setup do
    {:ok, family} = Ancestry.Families.create_family(%{name: "Test Family"})
    {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

    src = Path.absname("test/fixtures/test_image.jpg")
    uuid = Ecto.UUID.generate()
    dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, "photo.jpg")
    File.cp!(src, dest_path)

    on_exit(fn ->
      File.rm_rf!(dest_dir)
      File.rm_rf!(Path.join(["priv", "static", "uploads", "people", "#{person.id}"]))
    end)

    %{person: person, original_path: dest_path}
  end

  test "processes photo and broadcasts success", %{person: person, original_path: original_path} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")

    assert :ok =
             perform_job(ProcessPersonPhotoJob, %{
               person_id: person.id,
               original_path: original_path
             })

    updated = People.get_person!(person.id)
    assert updated.photo_status == "processed"
    assert updated.photo

    assert_receive {:person_photo_processed, _}
  end

  test "marks photo as failed when original_path is missing", %{person: person} do
    assert {:error, _} =
             ProcessPersonPhotoJob.perform(%Oban.Job{
               args: %{"person_id" => person.id, "original_path" => "/nonexistent/photo.jpg"}
             })

    updated = People.get_person!(person.id)
    assert updated.photo_status == "failed"
  end
end
