defmodule Ancestry.Handlers.AddGalleryToFamilyHandler do
  @moduledoc """
  Handles `Ancestry.Commands.AddGalleryToFamily`: insert the gallery, audit.
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
    |> Step.insert(:gallery, &add_gallery_to_family/1)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp add_gallery_to_family(%{envelope: envelope}) do
    %Gallery{}
    |> Gallery.changeset(Map.from_struct(envelope.command))
  end
end
