defmodule Ancestry.Workers.ProcessFamilyCoverJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.Families
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"family_id" => family_id, "original_path" => original_path}}) do
    family = Families.get_family!(family_id)

    case process_cover(family, original_path) do
      {:ok, updated_family} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "family:#{family.id}",
          {:cover_processed, updated_family}
        )

        :ok

      {:error, reason} ->
        {:ok, _} = Families.update_cover_failed(family)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "family:#{family.id}",
          {:cover_failed, family}
        )

        {:error, reason}
    end
  end

  defp process_cover(family, original_path) do
    {:ok, local_path, tmp_dir} = Ancestry.Storage.fetch_original(original_path)

    waffle_file = %{
      filename: Path.basename(local_path),
      path: local_path
    }

    result =
      case Uploaders.FamilyCover.store({waffle_file, family}) do
        {:ok, filename} -> Families.update_cover_processed(family, filename)
        {:error, reason} -> {:error, reason}
      end

    Ancestry.Storage.cleanup_original(tmp_dir)
    Ancestry.Storage.delete_original(original_path)

    result
  end
end
