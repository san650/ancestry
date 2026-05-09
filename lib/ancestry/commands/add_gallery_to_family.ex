defmodule Ancestry.Commands.AddGalleryToFamily do
  @moduledoc """
  Command to add a gallery to a family.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Gallery

  @enforce_keys [:family_id, :name]
  defstruct [:family_id, :name]

  @types %{family_id: :integer, name: :string}
  @required Map.keys(@types)

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, @required)
      |> Ecto.Changeset.validate_required(@required)
      |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)

    if cs.valid?,
      do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, attrs)

  @impl true
  def handled_by, do: Ancestry.Handlers.AddGalleryToFamilyHandler

  @impl true
  def primary_step, do: :gallery

  @impl true
  def permission, do: {:create, Gallery}
end
