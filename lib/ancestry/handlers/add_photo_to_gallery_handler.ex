defmodule Ancestry.Handlers.AddPhotoToGalleryHandler do
  @moduledoc """
  Handles `Ancestry.Commands.AddPhotoToGallery`: insert the photo,
  preload its gallery, schedule transform-and-store, audit.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo
  alias Ancestry.Workers.TransformAndStorePhoto

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.insert(:inserted_photo, &add_photo_to_gallery/1)
    |> Step.run(:photo, &preload_photo_gallery/2)
    |> Step.enqueue(:worker, &transform_and_store_photo/1)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp add_photo_to_gallery(%{envelope: envelope}) do
    %Photo{}
    |> Photo.changeset(Map.from_struct(envelope.command))
  end

  defp preload_photo_gallery(repo, %{inserted_photo: photo}) do
    {:ok, repo.preload(photo, :gallery)}
  end

  defp transform_and_store_photo(%{photo: photo}) do
    TransformAndStorePhoto.new(%{photo_id: photo.id})
  end
end
