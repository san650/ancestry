defmodule Ancestry.Commands.RemoveGalleryFromFamily do
  @moduledoc """
  Command to remove a gallery from a family.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Gallery

  @enforce_keys [:gallery_id]
  defstruct [:gallery_id]

  @types %{gallery_id: :integer}
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
  def handled_by, do: Ancestry.Handlers.RemoveGalleryFromFamilyHandler

  @impl true
  def primary_step, do: :gallery

  @impl true
  def permission, do: {:delete, Gallery}
end
