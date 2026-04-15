defmodule Ancestry.Comments do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Comments.PhotoComment

  def create_photo_comment(photo_id, account_id, attrs) do
    %PhotoComment{}
    |> PhotoComment.changeset(attrs)
    |> Ecto.Changeset.put_change(:photo_id, photo_id)
    |> Ecto.Changeset.put_change(:account_id, account_id)
    |> Repo.insert()
    |> case do
      {:ok, comment} ->
        comment = Repo.preload(comment, :account)

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
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:account]
    )
  end

  def get_photo_comment!(id), do: Repo.get!(PhotoComment, id) |> Repo.preload(:account)

  def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}) do
    PhotoComment.changeset(comment, attrs)
  end

  def update_photo_comment(%PhotoComment{} = comment, attrs) do
    comment
    |> PhotoComment.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, comment} ->
        comment = Repo.preload(comment, :account)

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
    comment = Repo.preload(comment, :account)

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
