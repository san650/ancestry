defmodule Ancestry.Commands.UpdatePhotoComment do
  @moduledoc """
  Command to update the text of an existing photo comment. Record-level
  authorization (owner-or-admin) is enforced inside the handler.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Comments.PhotoComment

  @enforce_keys [:photo_comment_id, :text]
  defstruct [:photo_comment_id, :text]

  @types %{photo_comment_id: :integer, text: :string}
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
  def handled_by, do: Ancestry.Handlers.UpdatePhotoCommentHandler

  @impl true
  def primary_step, do: :preloaded

  @impl true
  def permission, do: {:update, PhotoComment}
end
