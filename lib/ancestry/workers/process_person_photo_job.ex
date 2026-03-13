defmodule Ancestry.Workers.ProcessPersonPhotoJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.People
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"person_id" => person_id, "original_path" => original_path}}) do
    person = People.get_person!(person_id)

    case process_photo(person, original_path) do
      {:ok, updated_person} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "person:#{person.id}",
          {:person_photo_processed, updated_person}
        )

        :ok

      {:error, reason} ->
        {:ok, _} = People.update_photo_failed(person)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "person:#{person.id}",
          {:person_photo_failed, person}
        )

        {:error, reason}
    end
  end

  defp process_photo(person, original_path) do
    waffle_file = %{
      filename: Path.basename(original_path),
      path: original_path
    }

    case Uploaders.PersonPhoto.store({waffle_file, person}) do
      {:ok, filename} -> People.update_photo_processed(person, filename)
      {:error, reason} -> {:error, reason}
    end
  end
end
