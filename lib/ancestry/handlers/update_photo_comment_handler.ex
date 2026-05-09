defmodule Ancestry.Handlers.UpdatePhotoCommentHandler do
  @moduledoc """
  Handles `Ancestry.Commands.UpdatePhotoComment`: authorize + update +
  preload + broadcast.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.authorize(:authorized_comment, PhotoComment, :update, :photo_comment_id)
    |> Step.update(:updated_comment, &update_authorized_comment/1)
    |> Step.run(:comment, &preload_comment_account/2)
    |> Step.audit()
    |> Step.effects(&broadcast_update/2)
  end

  defp update_authorized_comment(%{envelope: envelope, authorized_comment: comment}) do
    PhotoComment.changeset(comment, %{text: envelope.command.text})
  end

  defp preload_comment_account(repo, %{updated_comment: comment}) do
    {:ok, repo.preload(comment, :account)}
  end

  defp broadcast_update(_repo, %{comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_updated, comment}}]}
  end
end
