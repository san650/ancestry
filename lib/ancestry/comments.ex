defmodule Ancestry.Comments do
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

  def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}) do
    PhotoComment.changeset(comment, attrs)
  end
end
