defmodule Ancestry.Handlers.TagPersonInPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.TagPersonInPhoto`: upsert the photo_person
  row by (photo_id, person_id), audit.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.PhotoPerson
  alias Ancestry.People.Person
  alias Ancestry.Repo

  @upsert_opts [
    on_conflict: {:replace, [:x, :y]},
    conflict_target: [:photo_id, :person_id],
    returning: true
  ]

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.insert(:photo_person, &tag_person_in_photo/1)
    |> Step.run(:tagged_person, &load_tagged_person/2)
    |> Step.audit(&audit_metadata/1)
    |> Step.no_effects()
  end

  defp tag_person_in_photo(%{envelope: envelope}) do
    cmd = envelope.command

    changeset =
      PhotoPerson.changeset(
        %PhotoPerson{photo_id: cmd.photo_id, person_id: cmd.person_id},
        %{x: cmd.x, y: cmd.y}
      )

    {changeset, @upsert_opts}
  end

  defp load_tagged_person(repo, %{envelope: envelope}) do
    {:ok, repo.get(Person, envelope.command.person_id)}
  end

  defp audit_metadata(%{tagged_person: person}),
    do: %{person_name: Person.display_name(person)}
end
