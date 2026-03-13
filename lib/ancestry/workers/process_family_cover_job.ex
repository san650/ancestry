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
    waffle_file = %{
      filename: Path.basename(original_path),
      path: original_path
    }

    case Uploaders.FamilyCover.store({waffle_file, family}) do
      {:ok, _filename} -> Families.update_cover_processed(family)
      {:error, reason} -> {:error, reason}
    end
  end
end
