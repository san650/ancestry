defmodule Ancestry.Workers.ProcessFamilyCoverJobTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.Families
  alias Ancestry.Workers.ProcessFamilyCoverJob

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    tmp_dir = Path.join(System.tmp_dir!(), "cover_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    src = Path.join(["test", "fixtures", "test_image.jpg"])
    dest = Path.join(tmp_dir, "cover.jpg")
    File.cp!(src, dest)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{family: family, tmp_path: dest}
  end

  test "processes cover photo and updates family status", %{family: family, tmp_path: tmp_path} do
    assert :ok =
             perform_job(ProcessFamilyCoverJob, %{
               family_id: family.id,
               original_path: tmp_path
             })

    updated = Families.get_family!(family.id)
    assert updated.cover_status == "processed"
    assert updated.cover
  end

  test "marks cover as failed when original_path is missing", %{family: family} do
    assert {:error, _} =
             ProcessFamilyCoverJob.perform(%Oban.Job{
               args: %{"family_id" => family.id, "original_path" => "/nonexistent/cover.jpg"}
             })

    updated = Families.get_family!(family.id)
    assert updated.cover_status == "failed"
  end
end
