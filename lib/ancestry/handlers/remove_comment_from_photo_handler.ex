defmodule Ancestry.Handlers.RemoveCommentFromPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemoveCommentFromPhoto`. Loads the target
  comment with its account preloaded, enforces the owner-or-admin
  record-level rule, deletes the row, and emits the broadcast effect
  with the preloaded snapshot so subscribers can update their views.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Envelope
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  @impl true
  def build_multi(%Envelope{command: cmd, scope: scope}) do
    Multi.new()
    |> Multi.put(:command, cmd)
    |> Multi.put(:scope, scope)
    |> Multi.run(:load, &load_with_account/2)
    |> Multi.run(:authorize, &authorize/2)
    |> Multi.delete(:photo_comment, fn %{load: c} -> c end)
    |> Multi.run(:__effects__, &compute_effects/2)
  end

  defp load_with_account(_repo, %{command: %{photo_comment_id: id}}) do
    case Repo.get(PhotoComment, id) do
      nil -> {:error, :not_found}
      c -> {:ok, Repo.preload(c, :account)}
    end
  end

  defp authorize(_repo, %{scope: scope, load: comment}) do
    if comment.account_id == scope.account.id or scope.account.role == :admin do
      {:ok, :authorized}
    else
      {:error, :unauthorized}
    end
  end

  defp compute_effects(_repo, %{photo_comment: c, load: loaded}) do
    {:ok,
     [
       {:broadcast, "photo_comments:#{c.photo_id}", {:comment_deleted, loaded}}
     ]}
  end
end
