defmodule Ancestry.Commands.DeletePhotoComment do
  @moduledoc """
  Command to delete an existing photo comment. Record-level
  authorization (owner-or-admin) is enforced inside the handler.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Comments.PhotoComment

  @enforce_keys [:photo_comment_id]
  defstruct [:photo_comment_id]

  @types %{photo_comment_id: :integer}
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
  def handled_by, do: Ancestry.Handlers.DeletePhotoCommentHandler

  @impl true
  def primary_step, do: :photo_comment

  @impl true
  def permission, do: {:delete, PhotoComment}
end
