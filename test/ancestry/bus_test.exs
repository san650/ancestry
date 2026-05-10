defmodule Ancestry.BusTest do
  use Ancestry.DataCase, async: false

  alias Ancestry.Bus
  alias Ancestry.Bus.Step
  alias Ancestry.Audit.Log

  defmodule NoopCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:label]
    defstruct [:label]

    @impl true
    def new(attrs) do
      cs =
        {%{}, %{label: :string}}
        |> Ecto.Changeset.cast(attrs, [:label])
        |> Ecto.Changeset.validate_required([:label])

      if cs.valid?,
        do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
        else: {:error, %{cs | action: :validate}}
    end

    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: Ancestry.BusTest.NoopHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  defmodule NoopHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.put(:result, %{label: envelope.command.label, ok: true})
      |> Step.audit()
      |> Step.no_effects()
    end
  end

  defmodule NotFoundHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.run(:boom, &not_found/2)
      |> Step.audit()
      |> Step.no_effects()
    end

    defp not_found(_repo, _changes), do: {:error, :not_found}
  end

  defmodule ChangesetHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.run(:cs, &changeset_error/2)
      |> Step.audit()
      |> Step.no_effects()
    end

    defp changeset_error(_repo, _changes) do
      cs = %Ecto.Changeset{data: %{}, types: %{}, valid?: false, action: :validate}
      {:error, Ecto.Changeset.add_error(cs, :base, "bad")}
    end
  end

  defmodule UnauthorizedStepHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.run(:authz, &unauthorized/2)
      |> Step.audit()
      |> Step.no_effects()
    end

    defp unauthorized(_repo, _changes), do: {:error, :unauthorized}
  end

  defmodule HandlerErrorHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.run(:weird, &something_else/2)
      |> Step.audit()
      |> Step.no_effects()
    end

    defp something_else(_repo, _changes), do: {:error, :something_else}
  end

  for {mod_name, handler} <- [
        {NotFoundCommand, NotFoundHandler},
        {ChangesetCommand, ChangesetHandler},
        {UnauthorizedCommand, UnauthorizedStepHandler},
        {HandlerErrorCommand, HandlerErrorHandler}
      ] do
    defmodule mod_name do
      use Ancestry.Bus.Command
      defstruct []
      @impl true
      def new(_), do: {:ok, %__MODULE__{}}
      @impl true
      def new!(_), do: %__MODULE__{}
      @impl true
      def handled_by, do: unquote(handler)
      @impl true
      def primary_step, do: :result
      @impl true
      def permission, do: {:read, Ancestry.Identity.Account}
    end
  end

  setup do
    {:ok, account} =
      %Ancestry.Identity.Account{
        email: "admin-bus-test@example.com",
        name: "Admin",
        role: :admin,
        hashed_password: Bcrypt.hash_pwd_salt("password")
      }
      |> Ancestry.Repo.insert()

    scope = %Ancestry.Identity.Scope{account: account, organization: nil}
    {:ok, scope: scope}
  end

  test "dispatch/2 returns the primary step result and writes an audit row", %{scope: scope} do
    {:ok, cmd} = NoopCommand.new(%{label: "hello"})

    assert {:ok, %{label: "hello", ok: true}} = Bus.dispatch(scope, cmd)

    assert [row] = Ancestry.Repo.all(Log)
    assert <<"cmd-", _::binary-size(36)>> = row.command_id
    assert row.command_module == "Ancestry.BusTest.NoopCommand"
    assert row.account_id == scope.account.id
    assert row.payload["arguments"] == %{"label" => "hello"}
    assert row.payload["metadata"] == %{}
  end

  test "classifies :not_found from a Multi step", %{scope: scope} do
    assert {:error, :not_found} = Bus.dispatch(scope, NotFoundCommand.new!(%{}))
    assert Ancestry.Repo.all(Log) == []
  end

  test "classifies a changeset failure as :validation", %{scope: scope} do
    assert {:error, :validation, %Ecto.Changeset{}} =
             Bus.dispatch(scope, ChangesetCommand.new!(%{}))
  end

  test "classifies :unauthorized from a Multi step", %{scope: scope} do
    assert {:error, :unauthorized} = Bus.dispatch(scope, UnauthorizedCommand.new!(%{}))
  end

  test "classifies unrecognized handler errors as :handler", %{scope: scope} do
    assert {:error, :handler, :something_else} =
             Bus.dispatch(scope, HandlerErrorCommand.new!(%{}))
  end

  defmodule DeniedCommand do
    use Ancestry.Bus.Command
    defstruct []

    @impl true
    def new(_), do: {:ok, %__MODULE__{}}
    @impl true
    def new!(_), do: %__MODULE__{}
    @impl true
    def handled_by, do: Ancestry.BusTest.NoopHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:delete, Ancestry.Organizations.Organization}
  end

  defmodule BroadcastingHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.put(:result, envelope.command)
      |> Step.audit()
      |> Step.effects(&broadcast_label/2)
    end

    defp broadcast_label(_repo, %{result: cmd}) do
      {:ok, [{:broadcast, "bus-test:#{cmd.label}", {:hello, cmd.label}}]}
    end
  end

  defmodule BroadcastingCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:label]
    defstruct [:label]
    @impl true
    def new(a), do: {:ok, struct!(__MODULE__, a)}
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: BroadcastingHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  test "fires broadcast effects after commit", %{scope: scope} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "bus-test:greeting")
    cmd = BroadcastingCommand.new!(%{label: "greeting"})

    assert {:ok, _} = Bus.dispatch(scope, cmd)
    assert_receive {:hello, "greeting"}, 500
  end

  defmodule WaffleDeleteHandler do
    use Ancestry.Bus.Handler
    alias Ancestry.Repo

    @impl true
    def handle(envelope) do
      envelope |> to_transaction() |> Repo.transaction()
    end

    defp to_transaction(envelope) do
      Step.new(envelope)
      |> Step.put(:result, %Ancestry.Galleries.Photo{image: nil})
      |> Step.audit()
      |> Step.effects(&clean_up_storage/2)
    end

    defp clean_up_storage(_repo, %{result: photo}) do
      {:ok, [{:waffle_delete, photo}]}
    end
  end

  defmodule WaffleDeleteCommand do
    use Ancestry.Bus.Command
    defstruct []
    @impl true
    def new(_), do: {:ok, %__MODULE__{}}
    @impl true
    def new!(_), do: %__MODULE__{}
    @impl true
    def handled_by, do: WaffleDeleteHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  test "fires :waffle_delete effects after commit (no-op when image is nil)", %{scope: scope} do
    cmd = WaffleDeleteCommand.new!(%{})
    assert {:ok, %Ancestry.Galleries.Photo{}} = Bus.dispatch(scope, cmd)
  end

  test "returns {:error, :unauthorized} when Permit denies" do
    {:ok, viewer} =
      %Ancestry.Identity.Account{
        email: "viewer-bus-test@example.com",
        name: "Viewer",
        role: :viewer,
        hashed_password: Bcrypt.hash_pwd_salt("password")
      }
      |> Ancestry.Repo.insert()

    viewer_scope = %Ancestry.Identity.Scope{account: viewer, organization: nil}
    cmd = DeniedCommand.new!(%{})
    assert {:error, :unauthorized} = Bus.dispatch(viewer_scope, cmd)
    assert Ancestry.Repo.all(Log) == []
  end

  describe "audit broadcast" do
    test "broadcasts on global topic when dispatch succeeds", %{scope: scope} do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

      {:ok, cmd} = NoopCommand.new(%{label: "broadcast-test"})
      assert {:ok, _} = Bus.dispatch(scope, cmd)

      assert_receive {:audit_logged, %Log{} = row}, 1_000
      assert row.account_id == scope.account.id
      assert row.command_module == "Ancestry.BusTest.NoopCommand"
      assert row.payload["arguments"][:label] == "broadcast-test"
    end

    test "broadcasts on org topic when scope has an organization" do
      organization = insert(:organization)

      {:ok, account} =
        %Ancestry.Identity.Account{
          email: "broadcast-org@example.com",
          name: "Org Admin",
          role: :admin,
          hashed_password: Bcrypt.hash_pwd_salt("password")
        }
        |> Ancestry.Repo.insert()

      scope = %Ancestry.Identity.Scope{account: account, organization: organization}

      Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log:org:#{organization.id}")

      {:ok, cmd} = NoopCommand.new(%{label: "org-test"})
      assert {:ok, _} = Bus.dispatch(scope, cmd)

      assert_receive {:audit_logged, %Log{} = row}, 1_000
      assert row.organization_id == organization.id
    end

    test "no broadcast when authorization is denied" do
      {:ok, viewer} =
        %Ancestry.Identity.Account{
          email: "viewer-broadcast@example.com",
          name: "Viewer",
          role: :viewer,
          hashed_password: Bcrypt.hash_pwd_salt("password")
        }
        |> Ancestry.Repo.insert()

      viewer_scope = %Ancestry.Identity.Scope{account: viewer, organization: nil}
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

      cmd = DeniedCommand.new!(%{})
      assert {:error, :unauthorized} = Bus.dispatch(viewer_scope, cmd)

      refute_receive {:audit_logged, _}, 200
    end

    test "no broadcast when handler step fails (:not_found)", %{scope: scope} do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

      cmd = NotFoundCommand.new!(%{})
      assert {:error, :not_found} = Bus.dispatch(scope, cmd)

      refute_receive {:audit_logged, _}, 200
    end
  end
end
