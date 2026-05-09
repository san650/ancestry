defmodule Ancestry.Bus.StepTest do
  use Ancestry.DataCase, async: true
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.Audit.Log
  alias Ancestry.Bus.{Envelope, Step}
  alias Ecto.Multi

  defmodule NoopWorker do
    use Oban.Worker, queue: :default
    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  defmodule FakeCommand do
    use Ancestry.Bus.Command

    @enforce_keys [:label]
    defstruct [:label]

    @impl true
    def new(_), do: raise("n/a")
    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  defmodule FakeAuthCommand do
    use Ancestry.Bus.Command

    @enforce_keys [:account_id]
    defstruct [:account_id]

    @impl true
    def new(_), do: raise("n/a")
    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :record
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  defp envelope, do: envelope_with(insert_account(:admin), FakeCommand.new!(%{label: "hello"}))

  defp authorize_envelope(account, target_id),
    do: envelope_with(account, FakeAuthCommand.new!(%{account_id: target_id}))

  defp envelope_with(account, command) do
    Envelope.wrap(%Ancestry.Identity.Scope{account: account, organization: nil}, command)
  end

  defp insert_account(role) do
    {:ok, account} =
      %Ancestry.Identity.Account{
        email: "step-test-#{System.unique_integer([:positive])}@example.com",
        role: role,
        hashed_password: Bcrypt.hash_pwd_salt("x")
      }
      |> Ancestry.Repo.insert()

    account
  end

  test "new/1 starts a Multi seeded with :envelope" do
    env = envelope()
    multi = Step.new(env)

    assert %Multi{} = multi
    assert multi |> Multi.to_list() |> Keyword.fetch!(:envelope) == {:put, env}
  end

  test "audit/1 appends an :audit insert step that builds an Audit.Log changeset" do
    env = envelope()
    multi = env |> Step.new() |> Step.audit()

    {:ok, %{audit: row}} = Ancestry.Repo.transaction(multi)
    assert %Log{command_id: cmd_id} = row
    assert cmd_id == env.command_id
  end

  test "no_effects/1 appends an :effects step returning []" do
    env = envelope()
    multi = env |> Step.new() |> Step.no_effects()

    {:ok, %{effects: effects}} = Ancestry.Repo.transaction(multi)
    assert effects == []
  end

  test "effects/2 appends an :effects step returning the function's result" do
    env = envelope()

    multi =
      env
      |> Step.new()
      |> Step.put(:thing, %{photo_id: 7})
      |> Step.effects(fn _repo, %{thing: t} ->
        {:ok, [{:broadcast, "test", {:hi, t.photo_id}}]}
      end)

    {:ok, %{effects: effects}} = Ancestry.Repo.transaction(multi)
    assert effects == [{:broadcast, "test", {:hi, 7}}]
  end

  test "authorize/5 returns the loaded record when the scope can perform the action" do
    admin = insert_account(:admin)
    target = insert_account(:viewer)
    env = authorize_envelope(admin, target.id)

    multi =
      env
      |> Step.new()
      |> Step.authorize(:record, Ancestry.Identity.Account, :read, :account_id)

    assert {:ok, %{record: record}} = Ancestry.Repo.transaction(multi)
    assert record.id == target.id
  end

  test "authorize/5 returns :not_found when the record does not exist" do
    admin = insert_account(:admin)
    env = authorize_envelope(admin, -1)

    multi =
      env
      |> Step.new()
      |> Step.authorize(:record, Ancestry.Identity.Account, :read, :account_id)

    assert {:error, :record, :not_found, _} = Ancestry.Repo.transaction(multi)
  end

  test "authorize/5 returns :unauthorized when the scope cannot perform the action" do
    viewer = insert_account(:viewer)
    target = insert_account(:viewer)
    env = authorize_envelope(viewer, target.id)

    multi =
      env
      |> Step.new()
      |> Step.authorize(:record, Ancestry.Identity.Account, :read, :account_id)

    assert {:error, :record, :unauthorized, _} = Ancestry.Repo.transaction(multi)
  end

  test "enqueue/3 schedules an Oban job atomically with the transaction" do
    env = envelope()

    multi =
      env
      |> Step.new()
      |> Step.enqueue(:job, fn _ -> NoopWorker.new(%{label: "x"}) end)

    {:ok, %{job: job}} = Ancestry.Repo.transaction(multi)
    assert %Oban.Job{worker: "Ancestry.Bus.StepTest.NoopWorker"} = job
    assert job.args == %{"label" => "x"}
  end
end
