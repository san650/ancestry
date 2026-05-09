defmodule Ancestry.Commands.UntagPersonFromPhoto do
  @moduledoc """
  Command to untag a person from a photo.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Photo

  @enforce_keys [:photo_id, :person_id]
  defstruct [:photo_id, :person_id]

  @types %{photo_id: :integer, person_id: :integer}
  @required Map.keys(@types)

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, @required)
      |> Ecto.Changeset.validate_required(@required)

    if cs.valid?,
      do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, attrs)

  @impl true
  def handled_by, do: Ancestry.Handlers.UntagPersonFromPhotoHandler

  @impl true
  def primary_step, do: :tag

  @impl true
  def permission, do: {:update, Photo}
end
