defmodule Ancestry.Comments do
  @moduledoc """
  Read-side context for photo comments. Mutations go through
  `Ancestry.Bus` and the `Ancestry.Commands.*PhotoComment` commands.
  """

  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Comments.PhotoComment

  def list_photo_comments(photo_id) do
    Repo.all(
      from c in PhotoComment,
        where: c.photo_id == ^photo_id,
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:account]
    )
  end

  def get_photo_comment!(id), do: Repo.get!(PhotoComment, id) |> Repo.preload(:account)

  def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}) do
    PhotoComment.changeset(comment, attrs)
  end
end
