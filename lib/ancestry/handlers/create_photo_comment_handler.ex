defmodule Ancestry.Handlers.CreatePhotoCommentHandler do
  @moduledoc """
  Handles `Ancestry.Commands.CreatePhotoComment` by inserting a
  `PhotoComment`, preloading its account, and computing the
  `:comment_created` broadcast effect.
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
    |> Multi.insert(:photo_comment, &insert_comment/1)
    |> Multi.run(:preloaded, &preload_account/2)
    |> Multi.run(:__effects__, &compute_effects/2)
  end

  defp insert_comment(%{command: cmd, scope: scope}) do
    %PhotoComment{}
    |> PhotoComment.changeset(%{text: cmd.text})
    |> Ecto.Changeset.put_change(:photo_id, cmd.photo_id)
    |> Ecto.Changeset.put_change(:account_id, scope.account.id)
  end

  defp preload_account(_repo, %{photo_comment: c}),
    do: {:ok, Repo.preload(c, :account)}

  defp compute_effects(_repo, %{preloaded: c}) do
    {:ok,
     [
       {:broadcast, "photo_comments:#{c.photo_id}", {:comment_created, c}}
     ]}
  end
end
