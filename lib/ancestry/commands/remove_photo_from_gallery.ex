defmodule Ancestry.Commands.RemovePhotoFromGallery do
  @moduledoc """
  Command to remove a photo from a gallery. Storage cleanup is fired
  post-commit by the dispatcher via the `:waffle_delete` effect.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Photo

  @enforce_keys [:photo_id]
  defstruct [:photo_id]

  @types %{photo_id: :integer}
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
  def handled_by, do: Ancestry.Handlers.RemovePhotoFromGalleryHandler

  @impl true
  def primary_step, do: :photo

  @impl true
  def permission, do: {:delete, Photo}
end
