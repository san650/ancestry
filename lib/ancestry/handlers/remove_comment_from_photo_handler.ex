defmodule Ancestry.Handlers.RemoveCommentFromPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemoveCommentFromPhoto`: authorize + load
  with account preloaded + delete + broadcast.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Authorization
  alias Ancestry.Bus.Step
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:authorized_comment, &authorize_comment_deletion/2)
    |> Step.run(:comment, &remove_authorized_comment/2)
    |> Step.audit()
    |> Step.effects(&broadcast_deletion/2)
  end

  defp authorize_comment_deletion(repo, %{envelope: envelope}) do
    %{command: command, scope: scope} = envelope

    case repo.get(PhotoComment, command.photo_comment_id) do
      nil ->
        {:error, :not_found}

      comment ->
        comment = repo.preload(comment, :account)

        if Authorization.can?(scope, :delete, comment),
          do: {:ok, comment},
          else: {:error, :unauthorized}
    end
  end

  defp remove_authorized_comment(repo, %{authorized_comment: comment}) do
    repo.delete(comment)
  end

  defp broadcast_deletion(_repo, %{authorized_comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_deleted, comment}}]}
  end
end
