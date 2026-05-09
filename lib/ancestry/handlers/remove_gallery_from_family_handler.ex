defmodule Ancestry.Handlers.RemoveGalleryFromFamilyHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemoveGalleryFromFamily`: find the gallery,
  delete it (FK cascade removes photos / photo_people / photo_comments),
  audit.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:gallery, &remove_gallery_from_family/2)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp remove_gallery_from_family(repo, %{envelope: envelope}) do
    case repo.get(Gallery, envelope.command.gallery_id) do
      nil -> {:error, :not_found}
      gallery -> repo.delete(gallery)
    end
  end
end
