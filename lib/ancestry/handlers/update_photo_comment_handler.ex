defmodule Ancestry.Handlers.UpdatePhotoCommentHandler do
  @moduledoc """
  Handles `Ancestry.Commands.UpdatePhotoComment`. Loads the target
  comment, enforces the owner-or-admin record-level rule, applies the
  update, preloads `:account`, and emits the broadcast effect.
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
    |> Multi.run(:load, &load_comment/2)
    |> Multi.run(:authorize, &authorize/2)
    |> Multi.update(:photo_comment, &update_changeset/1)
    |> Multi.run(:preloaded, &preload_account/2)
    |> Multi.run(:__effects__, &compute_effects/2)
  end

  defp load_comment(_repo, %{command: %{photo_comment_id: id}}) do
    case Repo.get(PhotoComment, id) do
      nil -> {:error, :not_found}
      c -> {:ok, c}
    end
  end

  defp authorize(_repo, %{scope: scope, load: comment}) do
    if comment.account_id == scope.account.id or scope.account.role == :admin do
      {:ok, :authorized}
    else
      {:error, :unauthorized}
    end
  end

  defp update_changeset(%{load: comment, command: cmd}),
    do: PhotoComment.changeset(comment, %{text: cmd.text})

  defp preload_account(_repo, %{photo_comment: c}),
    do: {:ok, Repo.preload(c, :account)}

  defp compute_effects(_repo, %{preloaded: c}) do
    {:ok,
     [
       {:broadcast, "photo_comments:#{c.photo_id}", {:comment_updated, c}}
     ]}
  end
end
