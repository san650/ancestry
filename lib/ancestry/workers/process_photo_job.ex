defmodule Ancestry.Workers.ProcessPhotoJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.Galleries
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    photo = Galleries.get_photo!(photo_id)

    case process_photo(photo) do
      {:ok, updated_photo} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "gallery:#{photo.gallery_id}",
          {:photo_processed, updated_photo}
        )

        :ok

      {:error, reason} ->
        {:ok, _} = Galleries.update_photo_failed(photo)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "gallery:#{photo.gallery_id}",
          {:photo_failed, photo}
        )

        {:error, reason}
    end
  end

  defp process_photo(photo) do
    waffle_file = %{
      filename: Path.basename(photo.original_path),
      path: photo.original_path
    }

    case Uploaders.Photo.store({waffle_file, photo}) do
      {:ok, filename} -> Galleries.update_photo_processed(photo, filename)
      {:error, reason} -> {:error, reason}
    end
  end
end
