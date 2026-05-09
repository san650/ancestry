defmodule Ancestry.Handlers.AddCommentToPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.AddCommentToPhoto`: insert the comment,
  preload its account, audit, broadcast its creation.
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
    |> Step.insert(:inserted_comment, &add_comment_to_photo/1)
    |> Step.run(:comment, &preload_comment_account/2)
    |> Step.audit()
    |> Step.effects(&broadcast_creation/2)
  end

  defp add_comment_to_photo(%{envelope: envelope}) do
    %{command: command, scope: scope} = envelope

    %PhotoComment{}
    |> PhotoComment.changeset(%{text: command.text})
    |> Ecto.Changeset.put_change(:photo_id, command.photo_id)
    |> Ecto.Changeset.put_change(:account_id, scope.account.id)
  end

  defp preload_comment_account(repo, %{inserted_comment: comment}) do
    {:ok, repo.preload(comment, :account)}
  end

  defp broadcast_creation(_repo, %{comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_created, comment}}]}
  end
end
