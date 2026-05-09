defmodule Ancestry.Commands.CreatePhotoComment do
  @moduledoc """
  Command to create a comment on a photo. Validated as a hybrid:
  command-level shape via embedded changeset; record-level changeset
  applied by the handler against `Ancestry.Comments.PhotoComment`.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Comments.PhotoComment

  @enforce_keys [:photo_id, :text]
  defstruct [:photo_id, :text]

  @types %{photo_id: :integer, text: :string}
  @required Map.keys(@types)

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, @required)
      |> Ecto.Changeset.validate_required(@required)
      |> Ecto.Changeset.validate_length(:text, max: 5000)

    if cs.valid?,
      do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, attrs)

  @impl true
  def handled_by, do: Ancestry.Handlers.CreatePhotoCommentHandler

  @impl true
  def primary_step, do: :preloaded

  @impl true
  def permission, do: {:create, PhotoComment}
end
