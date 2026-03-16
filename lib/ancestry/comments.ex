defmodule Ancestry.Comments do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Comments.PhotoComment

  def create_photo_comment(attrs) do
    %PhotoComment{}
    |> PhotoComment.changeset(attrs)
    |> Ecto.Changeset.put_change(:photo_id, attrs[:photo_id] || attrs["photo_id"])
    |> Repo.insert()
    |> case do
      {:ok, comment} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "photo_comments:#{comment.photo_id}",
          {:comment_created, comment}
        )

        {:ok, comment}

      error ->
        error
    end
  end

  def list_photo_comments(photo_id) do
    Repo.all(
      from c in PhotoComment,
        where: c.photo_id == ^photo_id,
        order_by: [asc: c.inserted_at, asc: c.id]
    )
  end

  def get_photo_comment!(id), do: Repo.get!(PhotoComment, id)

  def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}) do
    PhotoComment.changeset(comment, attrs)
  end

  def update_photo_comment(%PhotoComment{} = comment, attrs) do
    comment
    |> PhotoComment.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, comment} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "photo_comments:#{comment.photo_id}",
          {:comment_updated, comment}
        )

        {:ok, comment}

      error ->
        error
    end
  end

  def delete_photo_comment(%PhotoComment{} = comment) do
    Repo.delete(comment)
    |> case do
      {:ok, comment} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "photo_comments:#{comment.photo_id}",
          {:comment_deleted, comment}
        )

        {:ok, comment}

      error ->
        error
    end
  end
end
