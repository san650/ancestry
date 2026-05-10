defmodule Ancestry.Handlers.RemoveCommentFromPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemoveCommentFromPhoto`: authorize + delete +
  preload account + broadcast.
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
    |> Step.authorize(:authorized_comment, PhotoComment, :delete, :photo_comment_id)
    |> Step.run(:deleted_comment, &remove_authorized_comment/2)
    |> Step.run(:comment, &preload_comment_account/2)
    |> Step.audit(&audit_metadata/1)
    |> Step.effects(&broadcast_deletion/2)
  end

  defp audit_metadata(%{comment: comment}), do: %{text: comment.text}

  defp remove_authorized_comment(repo, %{authorized_comment: comment}) do
    repo.delete(comment)
  end

  defp preload_comment_account(repo, %{deleted_comment: comment}) do
    {:ok, repo.preload(comment, :account)}
  end

  defp broadcast_deletion(_repo, %{comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_deleted, comment}}]}
  end
end
