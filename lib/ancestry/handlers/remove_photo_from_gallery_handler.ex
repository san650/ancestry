defmodule Ancestry.Handlers.RemovePhotoFromGalleryHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemovePhotoFromGallery`: find the photo,
  delete it, audit, then clean up its storage post-commit via
  `:waffle_delete` effect.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.Photo
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:photo, &remove_photo_from_gallery/2)
    |> Step.audit()
    |> Step.effects(&clean_up_storage/2)
  end

  defp remove_photo_from_gallery(repo, %{envelope: envelope}) do
    case repo.get(Photo, envelope.command.photo_id) do
      nil -> {:error, :not_found}
      photo -> repo.delete(photo)
    end
  end

  defp clean_up_storage(_repo, %{photo: photo}) do
    if photo.image,
      do: {:ok, [{:waffle_delete, photo}]},
      else: {:ok, []}
  end
end
