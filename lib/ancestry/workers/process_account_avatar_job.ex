defmodule Ancestry.Workers.ProcessAccountAvatarJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.Identity
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "original_path" => original_path}}) do
    account = Identity.get_account!(account_id)

    case process_avatar(account, original_path) do
      {:ok, updated_account} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "account:#{account.id}",
          {:avatar_processed, updated_account}
        )

        :ok

      {:error, reason} ->
        {:ok, _} = Identity.update_avatar_status(account, "failed")

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "account:#{account.id}",
          {:avatar_failed, account}
        )

        {:error, reason}
    end
  end

  defp process_avatar(account, original_path) do
    {:ok, local_path, tmp_dir} = Ancestry.Storage.fetch_original(original_path)

    waffle_file = %{
      filename: Path.basename(local_path),
      path: local_path
    }

    result =
      case Uploaders.AccountAvatar.store({waffle_file, account}) do
        {:ok, filename} -> Identity.update_avatar_processed(account, filename)
        {:error, reason} -> {:error, reason}
      end

    Ancestry.Storage.cleanup_original(tmp_dir)
    Ancestry.Storage.delete_original(original_path)

    result
  end
end
