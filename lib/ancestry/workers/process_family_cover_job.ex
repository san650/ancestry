defmodule Ancestry.Workers.ProcessFamilyCoverJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"family_id" => _family_id, "original_path" => _original_path}}) do
    # TODO: Implement cover processing (Task 13)
    :ok
  end
end
