defmodule Ancestry.Handlers.UntagPersonFromPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.UntagPersonFromPhoto`: delete the
  photo_person row by (photo_id, person_id), audit. No-op when no
  tag exists.
  """

  use Ancestry.Bus.Handler

  import Ecto.Query

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.PhotoPerson
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:tag, &untag_person_from_photo/2)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp untag_person_from_photo(repo, %{envelope: envelope}) do
    cmd = envelope.command

    query =
      from pp in PhotoPerson,
        where: pp.photo_id == ^cmd.photo_id and pp.person_id == ^cmd.person_id

    {_count, _} = repo.delete_all(query)
    {:ok, :ok}
  end
end
