defmodule Ancestry.Commands.AddPhotoToGallery do
  @moduledoc """
  Command to add a photo to a gallery. Storage pre-flight (S3 upload) is
  the caller's responsibility; this command captures the resulting
  metadata so the handler can persist it.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Photo

  @enforce_keys [:gallery_id, :original_path, :original_filename, :content_type, :file_hash]
  defstruct [:gallery_id, :original_path, :original_filename, :content_type, :file_hash]

  @types %{
    gallery_id: :integer,
    original_path: :string,
    original_filename: :string,
    content_type: :string,
    file_hash: :string
  }
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
  def handled_by, do: Ancestry.Handlers.AddPhotoToGalleryHandler

  @impl true
  def primary_step, do: :photo

  @impl true
  def permission, do: {:create, Photo}
end
