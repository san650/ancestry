# Command/Handler Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the command/handler bus + audit log foundation, migrate all photo-comment mutations through it, and replace `Plug.RequestId` with prefixed request ids.

**Architecture:** A single `Ancestry.Bus.dispatch/3` dispatcher wraps every state mutation. Commands are plain structs validated by a hybrid (command-level changeset + entity changeset) flow. Handlers return an `Ecto.Multi` (no `Repo.transaction`); the dispatcher prepends an audit-row insert, runs the transaction, and fires post-commit side effects (PubSub broadcasts) from a `:__effects__` step. Authorization is dispatcher-level via Permit (coarse) plus a handler-level `:authorize` step (record-level). Audit rows land in a denormalized OLAP-style `audit_log` table, successes only; failures and request-stream metadata flow through `:telemetry` and `Logger`.

**Tech Stack:** Elixir 1.19, Phoenix 1.8 LiveView, Ecto + Ecto.Multi, Permit 0.3.3 + Permit.Phoenix 0.4.0, Phoenix.PubSub, Oban (existing — not used in this refactor), Postgres, Tailwind 4, ExUnit.

**Spec:** `docs/plans/2026-05-07-command-handler-foundation.md` (commit `2f764ea`). Read before starting.

**Branch:** `commands` (already exists).

---

## Pre-flight

The branch has staged/untracked WIP from an earlier prototype. Treat it as scaffolding to be replaced wholesale. Specifically:
- `lib/framework/{command,handler,types}.ex` — DELETE.
- `lib/ancestry/commands/create_photo_comment.ex` — DELETE (will be rewritten in Task 13).
- `lib/ancestry/handlers/create_photo_comment_handler.ex` — DELETE (will be rewritten in Task 14).
- `lib/ancestry/comments.ex` (modified) — KEEP the modification (mutation function removed); will fix imports in Task 22.
- `lib/web/live/comments/photo_comments_component.ex` (modified) — REVERT to pre-WIP; will be rewired in Tasks 15, 19, 23.
- `CLAUDE.md` (modified) — review and decide; not in scope of this refactor.
- `PERSONA.md` (untracked) — leave alone.

**Conventions for this plan:**
- Every TDD task: write test → run → see failure → implement → run → see pass → commit.
- Commits are small. Default style follows recent log (e.g., `Add Ancestry.Prefixes module`).
- Run `mix format` before committing.
- After every code-touching task: `mix compile --warnings-as-errors` must pass before the commit step.
- The final task runs `mix precommit`.

---

## Task 1: Pre-flight cleanup

**Files:**
- Delete: `lib/framework/command.ex`, `lib/framework/handler.ex`, `lib/framework/types.ex`
- Delete: `lib/ancestry/commands/create_photo_comment.ex`
- Delete: `lib/ancestry/handlers/create_photo_comment_handler.ex`
- Revert: `lib/web/live/comments/photo_comments_component.ex` to the version at `dc4a582` (`HEAD~1` after the design-doc commit).

- [ ] **Step 1:** Confirm baseline.

```bash
git status -s
git log --oneline -3
```
Expected: branch `commands`, doc commit at HEAD, WIP files visible per pre-flight notes.

- [ ] **Step 2:** Delete the WIP files.

```bash
rm -rf lib/framework
rm lib/ancestry/commands/create_photo_comment.ex
rm lib/ancestry/handlers/create_photo_comment_handler.ex
rmdir lib/ancestry/commands lib/ancestry/handlers 2>/dev/null || true
```

- [ ] **Step 3:** Revert the LiveView component to its pre-WIP state.

```bash
git checkout HEAD -- lib/web/live/comments/photo_comments_component.ex
```

- [ ] **Step 4:** Verify `lib/ancestry/comments.ex` retains the mutation removal (as in spec, queries-only). If still has `create_photo_comment/3`, leave for Task 22 — but verify it compiles standalone.

```bash
mix compile --warnings-as-errors
```
Expected: clean compile. If `comments.ex` still calls `create_photo_comment/3` from another callsite (it shouldn't — the LiveView is reverted), fix in this step before committing.

- [ ] **Step 5:** Commit cleanup.

```bash
git add -A
git commit -m "Remove WIP scaffolding before command/handler foundation"
```

---

## Task 2: `Ancestry.Prefixes` module

**Files:**
- Create: `lib/ancestry/prefixes.ex`
- Test: `test/ancestry/prefixes_test.exs`

- [ ] **Step 1:** Write the failing test.

```elixir
# test/ancestry/prefixes_test.exs
defmodule Ancestry.PrefixesTest do
  use ExUnit.Case, async: true

  alias Ancestry.Prefixes

  describe "for!/1" do
    test "returns the registered prefix" do
      assert Prefixes.for!(:command) == "cmd"
      assert Prefixes.for!(:request) == "req"
    end

    test "raises on unknown kind" do
      assert_raise FunctionClauseError, fn -> Prefixes.for!(:unknown) end
    end
  end

  describe "generate/1" do
    test "produces <prefix>-<uuid>" do
      id = Prefixes.generate(:command)
      assert <<"cmd-", uuid::binary-size(36)>> = id
      assert {:ok, _} = Ecto.UUID.cast(uuid)
    end

    test "successive calls produce unique ids" do
      refute Prefixes.generate(:request) == Prefixes.generate(:request)
    end
  end

  describe "parse!/1" do
    test "splits a registered id" do
      id = Prefixes.generate(:command)
      assert {"cmd", _uuid} = Prefixes.parse!(id)
    end

    test "raises on unknown prefix" do
      assert_raise ArgumentError, fn -> Prefixes.parse!("xyz-foo") end
    end
  end

  describe "known_kinds/0" do
    test "lists all registered kinds" do
      kinds = Prefixes.known_kinds()
      assert :command in kinds
      assert :request in kinds
    end
  end
end
```

- [ ] **Step 2:** Run the test, confirm failure.

```bash
mix test test/ancestry/prefixes_test.exs
```
Expected: `Ancestry.Prefixes is undefined`.

- [ ] **Step 3:** Implement.

```elixir
# lib/ancestry/prefixes.ex
defmodule Ancestry.Prefixes do
  @moduledoc """
  Single source of truth for prefixes used in external/exposed ids
  throughout the application. Format: `<prefix>-<uuid>`.

  Add an entry whenever introducing a new prefixed id. Compile-time
  checks enforce uniqueness and length (3–4 chars).
  """

  @prefixes %{
    command:      "cmd",
    request:      "req",
    account:      "acc",
    organization: "org",
    photo:        "pho",
    gallery:      "gal",
    family:       "fam",
    person:       "per",
    comment:      "com"
  }

  values = Map.values(@prefixes)

  case values -- Enum.uniq(values) do
    [] -> :ok
    dup -> raise "duplicate id prefixes: #{inspect(dup)}"
  end

  for v <- values, byte_size(v) not in 3..4,
    do: raise("id prefix must be 3 or 4 chars: #{inspect(v)}")

  @spec for!(atom()) :: String.t()
  def for!(kind) when is_map_key(@prefixes, kind), do: Map.fetch!(@prefixes, kind)

  @spec generate(atom()) :: String.t()
  def generate(kind), do: for!(kind) <> "-" <> Ecto.UUID.generate()

  @spec parse!(String.t()) :: {String.t(), String.t()}
  def parse!(id) when is_binary(id) do
    [prefix, rest] = String.split(id, "-", parts: 2)

    if prefix in Map.values(@prefixes),
      do: {prefix, rest},
      else: raise(ArgumentError, "unknown id prefix: #{inspect(prefix)} in #{inspect(id)}")
  end

  @spec known_kinds() :: [atom()]
  def known_kinds, do: Map.keys(@prefixes)
end
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/ancestry/prefixes_test.exs
mix compile --warnings-as-errors
```
Expected: 6 tests, 0 failures.

- [ ] **Step 5:** Commit.

```bash
mix format lib/ancestry/prefixes.ex test/ancestry/prefixes_test.exs
git add lib/ancestry/prefixes.ex test/ancestry/prefixes_test.exs
git commit -m "Add Ancestry.Prefixes registry for external id prefixes"
```

---

## Task 3: `Web.PrefixedRequestIdPlug` + endpoint swap

**Files:**
- Create: `lib/web/plugs/prefixed_request_id_plug.ex`
- Modify: `lib/web/endpoint.ex`
- Test: `test/web/plugs/prefixed_request_id_plug_test.exs`

- [ ] **Step 1:** Write the failing test.

```elixir
# test/web/plugs/prefixed_request_id_plug_test.exs
defmodule Web.PrefixedRequestIdPlugTest do
  use ExUnit.Case, async: false  # Logger.metadata is process-global
  use Plug.Test

  alias Web.PrefixedRequestIdPlug

  setup do
    Logger.metadata([])
    :ok
  end

  test "generates a req- prefixed id, sets logger metadata, sets response header" do
    conn = conn(:get, "/") |> PrefixedRequestIdPlug.call([])
    [request_id] = Plug.Conn.get_resp_header(conn, "x-request-id")

    assert <<"req-", _::binary-size(36)>> = request_id
    assert Logger.metadata()[:request_id] == request_id
    assert conn.assigns[:request_id] == request_id
  end

  test "preserves inbound x-request-id as :inbound_request_id metadata, replaces the active id" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.put_req_header("x-request-id", "upstream-12345")
      |> PrefixedRequestIdPlug.call([])

    [request_id] = Plug.Conn.get_resp_header(conn, "x-request-id")
    assert <<"req-", _::binary-size(36)>> = request_id
    assert Logger.metadata()[:request_id] == request_id
    assert Logger.metadata()[:inbound_request_id] == "upstream-12345"
  end

  test "ignores empty inbound x-request-id" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.put_req_header("x-request-id", "")
      |> PrefixedRequestIdPlug.call([])

    refute Logger.metadata()[:inbound_request_id]
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/web/plugs/prefixed_request_id_plug_test.exs
```
Expected: `Web.PrefixedRequestIdPlug is undefined`.

- [ ] **Step 3:** Implement.

```elixir
# lib/web/plugs/prefixed_request_id_plug.ex
defmodule Web.PrefixedRequestIdPlug do
  @behaviour Plug

  alias Ancestry.Prefixes
  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    request_id = Prefixes.generate(:request)

    metadata =
      case Plug.Conn.get_req_header(conn, "x-request-id") do
        [inbound | _] when byte_size(inbound) > 0 ->
          [request_id: request_id, inbound_request_id: inbound]

        _ ->
          [request_id: request_id]
      end

    Logger.metadata(metadata)

    conn
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
    |> Plug.Conn.assign(:request_id, request_id)
  end
end
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/web/plugs/prefixed_request_id_plug_test.exs
```
Expected: 3 tests, 0 failures.

- [ ] **Step 5:** Swap the endpoint plug.

In `lib/web/endpoint.ex`, replace:

```elixir
plug Plug.RequestId
```

with:

```elixir
plug Web.PrefixedRequestIdPlug
```

- [ ] **Step 6:** Run the full suite to confirm nothing else expected `Plug.RequestId`'s exact behavior.

```bash
mix test
mix compile --warnings-as-errors
```
Expected: green.

- [ ] **Step 7:** Commit.

```bash
mix format lib/web/plugs/prefixed_request_id_plug.ex test/web/plugs/prefixed_request_id_plug_test.exs lib/web/endpoint.ex
git add lib/web/plugs/prefixed_request_id_plug.ex test/web/plugs/prefixed_request_id_plug_test.exs lib/web/endpoint.ex
git commit -m "Replace Plug.RequestId with Web.PrefixedRequestIdPlug"
```

---

## Task 4: `Ancestry.Bus.Envelope`

**Files:**
- Create: `lib/ancestry/bus/envelope.ex`
- Test: `test/ancestry/bus/envelope_test.exs`

- [ ] **Step 1:** Write the failing test.

```elixir
# test/ancestry/bus/envelope_test.exs
defmodule Ancestry.Bus.EnvelopeTest do
  use ExUnit.Case, async: false  # Logger.metadata

  alias Ancestry.Bus.Envelope

  defmodule FakeCommand do
    defstruct [:foo]
  end

  setup do
    Logger.metadata([])
    :ok
  end

  test "wrap/2 builds an envelope with prefixed ids and current timestamp" do
    scope = %{account: %{id: 1}, organization: nil}
    command = %FakeCommand{foo: :bar}

    env = Envelope.wrap(scope, command)

    assert env.scope == scope
    assert env.command == command
    assert <<"cmd-", _::binary-size(36)>> = env.command_id
    assert <<"req-", _::binary-size(36)>> = env.correlation_id
    assert %DateTime{} = env.issued_at
  end

  test "wrap/3 honors :correlation_id from opts" do
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_id: "req-fixed")
    assert env.correlation_id == "req-fixed"
  end

  test "wrap/3 falls back to Logger.metadata[:request_id] when present" do
    Logger.metadata(request_id: "req-from-logger")
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{})
    assert env.correlation_id == "req-from-logger"
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/ancestry/bus/envelope_test.exs
```
Expected: `Ancestry.Bus.Envelope is undefined`.

- [ ] **Step 3:** Add a `@type t` to `Ancestry.Identity.Scope` if not already present (it isn't, as of this plan).

```elixir
# lib/ancestry/identity/scope.ex — add inside the module, before `defstruct`
@type t :: %__MODULE__{
        account: Account.t() | nil,
        organization: Ancestry.Organizations.Organization.t() | nil
      }
```

If `Account.t/0` or `Organization.t/0` are not defined, fall back to `term()` for that field. Verify with `mix compile --warnings-as-errors`.

- [ ] **Step 4:** Implement the envelope.

```elixir
# lib/ancestry/bus/envelope.ex
defmodule Ancestry.Bus.Envelope do
  alias Ancestry.Prefixes
  require Logger

  @enforce_keys [:scope, :command_id, :correlation_id, :issued_at, :command]
  defstruct [:scope, :command_id, :correlation_id, :issued_at, :command]

  @type t :: %__MODULE__{
          scope: Ancestry.Identity.Scope.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          issued_at: DateTime.t(),
          command: struct()
        }

  @spec wrap(term(), struct(), keyword()) :: t()
  def wrap(scope, command, opts \\ []) do
    %__MODULE__{
      scope: scope,
      command: command,
      command_id: Prefixes.generate(:command),
      correlation_id:
        opts[:correlation_id] || current_request_id() || Prefixes.generate(:request),
      issued_at: DateTime.utc_now()
    }
  end

  defp current_request_id, do: Logger.metadata()[:request_id]
end
```

- [ ] **Step 5:** Run, confirm pass.

```bash
mix test test/ancestry/bus/envelope_test.exs
```
Expected: 3 tests, 0 failures.

- [ ] **Step 6:** Commit.

```bash
mix format lib/ancestry/bus/envelope.ex test/ancestry/bus/envelope_test.exs lib/ancestry/identity/scope.ex
git add lib/ancestry/bus/envelope.ex test/ancestry/bus/envelope_test.exs lib/ancestry/identity/scope.ex
git commit -m "Add Ancestry.Bus.Envelope"
```

---

## Task 5: `Ancestry.Bus.Command` + `Ancestry.Bus.Handler` behaviours

**Files:**
- Create: `lib/ancestry/bus/command.ex`
- Create: `lib/ancestry/bus/handler.ex`

No test — behaviours-only (callbacks tested via concrete implementations later).

- [ ] **Step 1:** Implement `Ancestry.Bus.Command`.

```elixir
# lib/ancestry/bus/command.ex
defmodule Ancestry.Bus.Command do
  @callback new(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback new!(map() | keyword()) :: struct()
  @callback handled_by() :: module()
  @callback primary_step() :: atom()
  @callback permission() :: {atom(), module()}
  @callback redacted_fields() :: [atom()]
  @callback binary_fields() :: [atom()]

  @optional_callbacks redacted_fields: 0, binary_fields: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Command
      def redacted_fields, do: []
      def binary_fields, do: []
      defoverridable redacted_fields: 0, binary_fields: 0
    end
  end
end
```

- [ ] **Step 2:** Implement `Ancestry.Bus.Handler`.

```elixir
# lib/ancestry/bus/handler.ex
defmodule Ancestry.Bus.Handler do
  @callback build_multi(Ancestry.Bus.Envelope.t()) :: Ecto.Multi.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Handler
      alias Ecto.Multi
    end
  end
end
```

- [ ] **Step 3:** Confirm compile.

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4:** Commit.

```bash
mix format lib/ancestry/bus/command.ex lib/ancestry/bus/handler.ex
git add lib/ancestry/bus/command.ex lib/ancestry/bus/handler.ex
git commit -m "Add Ancestry.Bus.Command and Handler behaviours"
```

---

## Task 6: `audit_log` migration + `Ancestry.Audit.Log` schema

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_audit_log.exs`
- Create: `lib/ancestry/audit/log.ex`
- Test: `test/ancestry/audit/log_test.exs`

- [ ] **Step 1:** Generate the migration.

```bash
mix ecto.gen.migration create_audit_log
```

The generated file will be `priv/repo/migrations/<timestamp>_create_audit_log.exs`.

- [ ] **Step 2:** Fill the migration.

```elixir
defmodule Ancestry.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def change do
    create table(:audit_log) do
      add :command_id,        :string,  null: false   # "cmd-<uuid>"
      add :correlation_id,    :string,  null: false   # "req-<uuid>"
      add :command_module,    :string,  null: false
      add :account_id,        :bigint,  null: false   # denormalized; no FK
      add :account_name,      :string,  null: true    # Account.name is nullable
      add :account_email,     :string,  null: false
      add :organization_id,   :bigint,  null: true
      add :organization_name, :string,  null: true
      add :payload,           :map,     null: false
      add :inserted_at,       :utc_datetime_usec, null: false
    end

    create unique_index(:audit_log, [:command_id])
    create index(:audit_log, [:correlation_id])
    create index(:audit_log, [:account_id, :inserted_at])
    create index(:audit_log, [:organization_id, :inserted_at])
    create index(:audit_log, [:command_module, :inserted_at])
  end
end
```

- [ ] **Step 3:** Run the migration.

```bash
mix ecto.migrate
```
Expected: `audit_log` created.

- [ ] **Step 4:** Write the failing schema test.

```elixir
# test/ancestry/audit/log_test.exs
defmodule Ancestry.Audit.LogTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Audit.Log
  alias Ancestry.Bus.Envelope

  defmodule FakeCommand do
    use Ancestry.Bus.Command

    @enforce_keys [:foo]
    defstruct [:foo]

    @impl true
    def new(_), do: raise "not used"
    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :foo
    @impl true
    def permission, do: {:test, FakeCommand}
  end

  test "changeset_from/1 builds a valid changeset from an envelope (org-scoped)" do
    account = %{id: 1, name: "Alice", email: "alice@example.com"}
    org = %{id: 9, name: "Acme"}
    scope = %{account: account, organization: org}
    cmd = FakeCommand.new!(%{foo: "bar"})
    env = Envelope.wrap(scope, cmd)

    cs = Log.changeset_from(env)
    assert cs.valid?
    {:ok, row} = Ancestry.Repo.insert(cs)

    assert row.command_id == env.command_id
    assert row.correlation_id == env.correlation_id
    assert row.command_module == "Ancestry.Audit.LogTest.FakeCommand"
    assert row.account_id == 1
    assert row.account_name == "Alice"
    assert row.account_email == "alice@example.com"
    assert row.organization_id == 9
    assert row.organization_name == "Acme"
    assert row.payload == %{foo: "bar"}
  end

  test "changeset_from/1 allows nil organization (top-level command)" do
    scope = %{account: %{id: 2, name: nil, email: "bob@x.com"}, organization: nil}
    cmd = FakeCommand.new!(%{foo: "ok"})
    env = Envelope.wrap(scope, cmd)

    cs = Log.changeset_from(env)
    assert cs.valid?
    {:ok, row} = Ancestry.Repo.insert(cs)

    assert is_nil(row.organization_id)
    assert is_nil(row.organization_name)
    assert is_nil(row.account_name)
  end
end
```

- [ ] **Step 5:** Run, confirm failure.

```bash
mix test test/ancestry/audit/log_test.exs
```
Expected: `Ancestry.Audit.Log is undefined`.

- [ ] **Step 6:** Implement the schema.

```elixir
# lib/ancestry/audit/log.ex
defmodule Ancestry.Audit.Log do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ancestry.Audit.Serializer

  schema "audit_log" do
    field :command_id,        :string
    field :correlation_id,    :string
    field :command_module,    :string
    field :account_id,        :integer
    field :account_name,      :string
    field :account_email,     :string
    field :organization_id,   :integer
    field :organization_name, :string
    field :payload,           :map

    timestamps(updated_at: false)
  end

  @required ~w(command_id correlation_id command_module account_id account_email payload)a
  @optional ~w(account_name organization_id organization_name)a

  def changeset_from(envelope) do
    %__MODULE__{}
    |> cast(attrs_from(envelope), @required ++ @optional)
    |> validate_required(@required)
  end

  defp attrs_from(env) do
    %{
      command_id:        env.command_id,
      correlation_id:    env.correlation_id,
      command_module:    inspect(env.command.__struct__),
      account_id:        env.scope.account.id,
      account_name:      env.scope.account.name,
      account_email:     env.scope.account.email,
      organization_id:   org_id(env.scope),
      organization_name: org_name(env.scope),
      payload:           Serializer.serialize(env.command)
    }
  end

  defp org_id(%{organization: %{id: id}}),    do: id
  defp org_id(_),                             do: nil
  defp org_name(%{organization: %{name: n}}), do: n
  defp org_name(_),                           do: nil
end
```

- [ ] **Step 7:** Skip ahead briefly to define `Ancestry.Audit.Serializer` so the test compiles. Stub for now; full TDD in Task 7.

```elixir
# lib/ancestry/audit/serializer.ex (stub — fully implemented next task)
defmodule Ancestry.Audit.Serializer do
  def serialize(%_{} = cmd) do
    cmd |> Map.from_struct()
  end
end
```

- [ ] **Step 8:** Run, confirm pass.

```bash
mix test test/ancestry/audit/log_test.exs
```
Expected: 2 tests, 0 failures.

- [ ] **Step 9:** Commit.

```bash
mix format
git add priv/repo/migrations/*_create_audit_log.exs lib/ancestry/audit/log.ex lib/ancestry/audit/serializer.ex test/ancestry/audit/log_test.exs
git commit -m "Add audit_log table and Ancestry.Audit.Log schema"
```

---

## Task 7: `Ancestry.Audit.Serializer` (full implementation)

**Files:**
- Modify: `lib/ancestry/audit/serializer.ex`
- Test: `test/ancestry/audit/serializer_test.exs`

- [ ] **Step 1:** Write the failing test.

```elixir
# test/ancestry/audit/serializer_test.exs
defmodule Ancestry.Audit.SerializerTest do
  use ExUnit.Case, async: true

  alias Ancestry.Audit.Serializer

  defmodule SimpleCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:photo_id, :text]
    defstruct [:photo_id, :text]
    @impl true
    def new(_), do: raise "n/a"
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, SimpleCommand}
  end

  defmodule RedactedCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:email, :password]
    defstruct [:email, :password]
    @impl true
    def new(_), do: raise "n/a"
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, RedactedCommand}
    @impl true
    def redacted_fields, do: [:password]
  end

  defmodule BlobCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:label, :photo]
    defstruct [:label, :photo]
    @impl true
    def new(_), do: raise "n/a"
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, BlobCommand}
    @impl true
    def binary_fields, do: [:photo]
  end

  test "serializes a plain command into a map of its fields (no __struct__)" do
    cmd = SimpleCommand.new!(%{photo_id: 7, text: "hi"})
    assert Serializer.serialize(cmd) == %{photo_id: 7, text: "hi"}
  end

  test "redacts fields listed in redacted_fields/0" do
    cmd = RedactedCommand.new!(%{email: "a@b.c", password: "secret"})
    assert Serializer.serialize(cmd) == %{email: "a@b.c", password: "[redacted]"}
  end

  test "replaces fields listed in binary_fields/0 with the binary-blob marker" do
    cmd = BlobCommand.new!(%{label: "x", photo: <<1, 2, 3>>})
    assert Serializer.serialize(cmd) == %{label: "x", photo: "binary-blob"}
  end
end
```

- [ ] **Step 2:** Run, confirm failure (the stub does not redact).

```bash
mix test test/ancestry/audit/serializer_test.exs
```
Expected: 2 of 3 fail (redaction and blob tests).

- [ ] **Step 3:** Implement the real serializer.

```elixir
# lib/ancestry/audit/serializer.ex
defmodule Ancestry.Audit.Serializer do
  @moduledoc """
  Serializes a command struct to a map suitable for jsonb storage.
  Replaces redacted fields with "[redacted]" and binary blobs with
  "binary-blob".
  """

  def serialize(%module{} = cmd) do
    redacted = MapSet.new(module.redacted_fields())
    binaries = MapSet.new(module.binary_fields())

    cmd
    |> Map.from_struct()
    |> Map.new(fn {k, v} ->
      cond do
        k in redacted -> {k, "[redacted]"}
        k in binaries -> {k, "binary-blob"}
        true          -> {k, v}
      end
    end)
  end
end
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/ancestry/audit/serializer_test.exs
```
Expected: 3 tests, 0 failures.

- [ ] **Step 5:** Commit.

```bash
mix format lib/ancestry/audit/serializer.ex test/ancestry/audit/serializer_test.exs
git add lib/ancestry/audit/serializer.ex test/ancestry/audit/serializer_test.exs
git commit -m "Add Ancestry.Audit.Serializer with redaction and binary-blob handling"
```

---

## Task 8: `Ancestry.Bus` dispatcher — happy path with audit row

**Files:**
- Create: `lib/ancestry/bus.ex`
- Test: `test/ancestry/bus_test.exs`

- [ ] **Step 1:** Write the failing test for the success path.

```elixir
# test/ancestry/bus_test.exs
defmodule Ancestry.BusTest do
  use Ancestry.DataCase, async: false  # Logger.metadata + telemetry

  alias Ancestry.Bus
  alias Ancestry.Audit.Log
  alias Ecto.Multi

  # Minimal command + handler that doesn't touch real domain models.
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
    def permission, do: {:read, NoopCommand}
  end

  defmodule NoopHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(%Ancestry.Bus.Envelope{command: cmd}) do
      Multi.new()
      |> Multi.put(:result, %{label: cmd.label, ok: true})
      |> Multi.run(:__effects__, fn _, _ -> {:ok, []} end)
    end
  end

  setup do
    # Allow :read on NoopCommand for any scope by stubbing Authorization.
    # Easiest: insert an admin-role account.
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
    assert row.payload == %{label: "hello"}
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/ancestry/bus_test.exs
```
Expected: `Ancestry.Bus is undefined`.

- [ ] **Step 3:** Implement the minimal happy-path dispatcher.

```elixir
# lib/ancestry/bus.ex
defmodule Ancestry.Bus do
  alias Ancestry.{Authorization, Repo}
  alias Ancestry.Audit
  alias Ancestry.Bus.Envelope
  alias Ecto.Multi
  require Logger

  def dispatch(scope, command, opts \\ []),
    do: dispatch_envelope(Envelope.wrap(scope, command, opts))

  def dispatch_envelope(%Envelope{command: %module{}} = env) do
    Logger.metadata(
      command_id: env.command_id,
      correlation_id: env.correlation_id,
      command_module: inspect(module)
    )

    :telemetry.span(
      [:ancestry, :bus, :dispatch],
      base_metadata(env),
      fn ->
        result = do_dispatch(env, module)
        {result, Map.merge(base_metadata(env), outcome_metadata(result))}
      end
    )
  end

  defp do_dispatch(env, module) do
    {action, resource} = module.permission()

    if Authorization.can?(env.scope, action, resource) do
      run(env, module)
    else
      Logger.warning("authz_denied",
        command_id: env.command_id,
        command_module: inspect(module),
        action: action,
        resource: inspect(resource)
      )

      {:error, :unauthorized}
    end
  end

  defp run(env, module) do
    multi =
      module.handled_by().build_multi(env)
      |> Multi.insert(:__audit__, fn _ -> Audit.Log.changeset_from(env) end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        Enum.each(changes[:__effects__] || [], &run_effect/1)
        {:ok, Map.fetch!(changes, module.primary_step())}

      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, :validation, cs}
      {:error, _step, :not_found, _}             -> {:error, :not_found}
      {:error, _step, {:not_found, _}, _}        -> {:error, :not_found}
      {:error, _step, :unauthorized, _}          -> {:error, :unauthorized}
      {:error, _step, {:conflict, t}, _}         -> {:error, :conflict, t}
      {:error, _step, other, _}                  -> {:error, :handler, other}
    end
  end

  defp run_effect({:broadcast, topic, msg}),
    do: Phoenix.PubSub.broadcast(Ancestry.PubSub, topic, msg)

  defp base_metadata(env) do
    %{
      command_id: env.command_id,
      correlation_id: env.correlation_id,
      command_module: inspect(env.command.__struct__),
      account_id: env.scope.account.id,
      organization_id: scope_org_id(env.scope)
    }
  end

  defp outcome_metadata({:ok, _}),         do: %{outcome: :ok, error_tag: nil}
  defp outcome_metadata({:error, tag}),    do: %{outcome: :error, error_tag: tag}
  defp outcome_metadata({:error, tag, _}), do: %{outcome: :error, error_tag: tag}

  defp scope_org_id(%{organization: %{id: id}}), do: id
  defp scope_org_id(_),                          do: nil
end
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/ancestry/bus_test.exs
```
Expected: 1 test, 0 failures.

- [ ] **Step 5:** Commit.

```bash
mix format lib/ancestry/bus.ex test/ancestry/bus_test.exs
git add lib/ancestry/bus.ex test/ancestry/bus_test.exs
git commit -m "Add Ancestry.Bus dispatcher with audit row write"
```

---

## Task 9: Dispatcher — error classification tests

**Files:**
- Modify: `test/ancestry/bus_test.exs`

The dispatcher already classifies errors (Task 8). This task locks the contract with explicit tests.

- [ ] **Step 1:** Append to `test/ancestry/bus_test.exs` — both helper modules (handlers + commands) AND tests. Define the helpers at the top of the file alongside `NoopCommand` / `NoopHandler`. Each error case needs one Handler module + one Command module pointing at it.

```elixir
# Helper handlers — append next to NoopHandler.

defmodule NotFoundHandler do
  use Ancestry.Bus.Handler

  @impl true
  def build_multi(_env) do
    Multi.new()
    |> Multi.run(:boom, fn _, _ -> {:error, :not_found} end)
  end
end

defmodule ChangesetHandler do
  use Ancestry.Bus.Handler

  @impl true
  def build_multi(_env) do
    Multi.new()
    |> Multi.run(:cs, fn _, _ ->
      cs = %Ecto.Changeset{data: %{}, types: %{}, valid?: false, action: :validate}
      {:error, Ecto.Changeset.add_error(cs, :base, "bad")}
    end)
  end
end

defmodule UnauthorizedStepHandler do
  use Ancestry.Bus.Handler

  @impl true
  def build_multi(_env) do
    Multi.new()
    |> Multi.run(:authz, fn _, _ -> {:error, :unauthorized} end)
  end
end

defmodule HandlerErrorHandler do
  use Ancestry.Bus.Handler

  @impl true
  def build_multi(_env) do
    Multi.new()
    |> Multi.run(:weird, fn _, _ -> {:error, :something_else} end)
  end
end

# Helper commands — copy NoopCommand verbatim and change handled_by/0.
# Each command keeps the same {:read, NoopCommand} permission so the
# dispatcher's class-level Permit check passes uniformly for the admin
# scope set up in the suite.

for {mod_name, handler} <- [
      {NotFoundCommand,   NotFoundHandler},
      {ChangesetCommand,  ChangesetHandler},
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
    def permission, do: {:read, Ancestry.BusTest.NoopCommand}
  end
end
```

Then the tests:

```elixir
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
```

If the test file approaches ~300 lines, extract these helpers into `test/support/bus_test_helpers.ex` and reference them from the test.

- [ ] **Step 2:** Run, confirm pass (the dispatcher already classifies).

```bash
mix test test/ancestry/bus_test.exs
```

- [ ] **Step 3:** Commit.

```bash
mix format test/ancestry/bus_test.exs
git add test/ancestry/bus_test.exs
git commit -m "Lock Ancestry.Bus error taxonomy with explicit tests"
```

---

## Task 10: Dispatcher — authz denial test

**Files:**
- Modify: `test/ancestry/bus_test.exs`

- [ ] **Step 1:** Add a test where Permit denies the action.

```elixir
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
  def permission, do: {:dangerous_action, Ancestry.Identity.Account}
end

test "returns {:error, :unauthorized} when Permit denies", %{scope: scope} do
  # Even an admin should not have :dangerous_action in Ancestry.Permissions.
  cmd = DeniedCommand.new!(%{})
  assert {:error, :unauthorized} = Bus.dispatch(scope, cmd)
  assert Ancestry.Repo.all(Log) == []
end
```

- [ ] **Step 2:** Run, confirm pass.

```bash
mix test test/ancestry/bus_test.exs
```

- [ ] **Step 3:** Commit.

```bash
git add test/ancestry/bus_test.exs
git commit -m "Test Ancestry.Bus authz denial path"
```

---

## Task 11: Dispatcher — post-commit effects

**Files:**
- Modify: `test/ancestry/bus_test.exs`

The dispatcher already fires `:__effects__`. This task verifies it.

- [ ] **Step 1:** Add a test that subscribes to PubSub and asserts a broadcast.

```elixir
defmodule BroadcastingHandler do
  use Ancestry.Bus.Handler

  @impl true
  def build_multi(%Ancestry.Bus.Envelope{command: cmd}) do
    Multi.new()
    |> Multi.put(:result, cmd)
    |> Multi.run(:__effects__, fn _, _ ->
      {:ok, [{:broadcast, "bus-test:#{cmd.label}", {:hello, cmd.label}}]}
    end)
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
  def permission, do: {:read, Ancestry.BusTest.NoopCommand}  # reuse a permitted action
end

test "fires broadcast effects after commit", %{scope: scope} do
  Phoenix.PubSub.subscribe(Ancestry.PubSub, "bus-test:greeting")
  cmd = BroadcastingCommand.new!(%{label: "greeting"})

  assert {:ok, _} = Bus.dispatch(scope, cmd)
  assert_receive {:hello, "greeting"}, 500
end
```

- [ ] **Step 2:** Run, confirm pass.

```bash
mix test test/ancestry/bus_test.exs
```

- [ ] **Step 3:** Commit.

```bash
git add test/ancestry/bus_test.exs
git commit -m "Test Ancestry.Bus post-commit effects firing"
```

---

## Task 12: `Ancestry.Permissions` — keep current rules

**Files:**
- Modify: `lib/ancestry/permissions.ex` (no code changes — only locking assumptions)

**Authorization strategy used by this plan (locked):**

The spec offers two paths for the owner-vs-admin rule on PhotoComment update/delete:
1. Add owner-conditioned record-level clauses to `Ancestry.Permissions` (requires Permit record-level DSL — uncertain support in 0.3.3).
2. Keep `Ancestry.Permissions` class-level only and enforce the owner rule inline in each handler's `:authorize` Multi step.

**This plan takes path 2** — the inline-handler fallback. Rationale: avoids version-coupling to Permit; keeps the change surface small; the spec documents this fallback explicitly. The handler-inline check does NOT call `Authorization.can?` again because the class-level rule already passed in the dispatcher (and would pass for any editor on any record per the `all(PhotoComment)` rule).

Current `Ancestry.Permissions`:
- `:admin` → `all(PhotoComment)` (class-level).
- `:editor` → `all(PhotoComment)` (class-level — fine; record-level enforced in handler).
- `:viewer` → `read(PhotoComment) |> create(PhotoComment)` (class-level — viewers cannot reach the update/delete handlers because the dispatcher class-level check denies them).

No code changes needed in this task — only lock the assumption with an explicit test.

**Files:**
- Test: `test/ancestry/permissions_test.exs` (create or extend)

- [ ] **Step 1:** Write tests confirming the class-level rules.

```elixir
# test/ancestry/permissions_test.exs
defmodule Ancestry.PermissionsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Authorization
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Identity.{Account, Scope}

  defp scope(role) do
    %Scope{
      account: %Account{id: 1, role: role, email: "x@y.z"},
      organization: nil
    }
  end

  test "admin can update and delete PhotoComment at class level" do
    assert Authorization.can?(scope(:admin), :update, PhotoComment)
    assert Authorization.can?(scope(:admin), :delete, PhotoComment)
  end

  test "editor can update and delete PhotoComment at class level (record-level enforced in handler)" do
    assert Authorization.can?(scope(:editor), :update, PhotoComment)
    assert Authorization.can?(scope(:editor), :delete, PhotoComment)
  end

  test "viewer can create PhotoComment but not update/delete at class level" do
    assert Authorization.can?(scope(:viewer), :create, PhotoComment)
    refute Authorization.can?(scope(:viewer), :update, PhotoComment)
    refute Authorization.can?(scope(:viewer), :delete, PhotoComment)
  end
end
```

- [ ] **Step 2:** Run, confirm pass.

```bash
mix test test/ancestry/permissions_test.exs
```

If a test fails, the existing `Ancestry.Permissions` clauses must be adjusted in this task — but per the spec the existing rules already match (editor: `all(PhotoComment)`, viewer: `read(PhotoComment) |> create(PhotoComment)`).

- [ ] **Step 3:** Commit.

```bash
mix format test/ancestry/permissions_test.exs
git add test/ancestry/permissions_test.exs
git commit -m "Lock Ancestry.Permissions PhotoComment class-level rules"
```

---

## Task 13: `Ancestry.Commands.CreatePhotoComment`

**Files:**
- Create: `lib/ancestry/commands/create_photo_comment.ex`
- Test: `test/ancestry/commands/create_photo_comment_test.exs`

- [ ] **Step 1:** Write the failing test.

```elixir
# test/ancestry/commands/create_photo_comment_test.exs
defmodule Ancestry.Commands.CreatePhotoCommentTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.CreatePhotoComment

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = CreatePhotoComment.new(%{photo_id: 1, text: "hi"})
    assert %CreatePhotoComment{photo_id: 1, text: "hi"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = CreatePhotoComment.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:photo_id]
    assert {"can't be blank", _} = cs.errors[:text]
  end

  test "new/1 enforces text length max" do
    long = String.duplicate("a", 5001)
    assert {:error, cs} = CreatePhotoComment.new(%{photo_id: 1, text: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:text]
  end

  test "primary_step/0 == :preloaded" do
    assert CreatePhotoComment.primary_step() == :preloaded
  end

  test "permission/0 == {:create, PhotoComment}" do
    assert CreatePhotoComment.permission() == {:create, Ancestry.Comments.PhotoComment}
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/ancestry/commands/create_photo_comment_test.exs
```

- [ ] **Step 3:** Implement.

```elixir
# lib/ancestry/commands/create_photo_comment.ex
defmodule Ancestry.Commands.CreatePhotoComment do
  use Ancestry.Bus.Command

  alias Ancestry.Comments.PhotoComment

  @enforce_keys [:photo_id, :text]
  defstruct [:photo_id, :text]

  @types %{photo_id: :integer, text: :string}
  @required Map.keys(@types)

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, @required)
      |> Ecto.Changeset.validate_required(@required)
      |> Ecto.Changeset.validate_length(:text, max: 5000)

    if cs.valid?,
      do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, attrs)

  @impl true
  def handled_by, do: Ancestry.Handlers.CreatePhotoCommentHandler

  @impl true
  def primary_step, do: :preloaded

  @impl true
  def permission, do: {:create, PhotoComment}
end
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/ancestry/commands/create_photo_comment_test.exs
```

- [ ] **Step 5:** Commit.

```bash
mix format lib/ancestry/commands/create_photo_comment.ex test/ancestry/commands/create_photo_comment_test.exs
git add lib/ancestry/commands/create_photo_comment.ex test/ancestry/commands/create_photo_comment_test.exs
git commit -m "Add Ancestry.Commands.CreatePhotoComment"
```

---

## Task 14: `Ancestry.Handlers.CreatePhotoCommentHandler`

**Files:**
- Create: `lib/ancestry/handlers/create_photo_comment_handler.ex`
- Test: `test/ancestry/handlers/create_photo_comment_handler_test.exs`

- [ ] **Step 1:** Inspect the existing factory before writing the test. The codebase has `test/support/factory.ex` (or similar) used by the existing user-flow tests. Mirror its setup helpers rather than hand-rolling fixtures.

```bash
ls test/support/
grep -rl "def insert\|defp create_" test/support/ test/user_flows/
```

Use whatever account/organization/family/gallery/photo helpers you find. The shape below is a placeholder; replace with the real factory calls.

- [ ] **Step 2:** Write the failing test.

```elixir
# test/ancestry/handlers/create_photo_comment_handler_test.exs
defmodule Ancestry.Handlers.CreatePhotoCommentHandlerTest do
  use Ancestry.DataCase, async: false  # PubSub assertions

  alias Ancestry.Bus.Envelope
  alias Ancestry.Commands.CreatePhotoComment
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Handlers.CreatePhotoCommentHandler

  setup do
    # Replace with project factory helpers. Required: account (admin role for
    # this test to pass dispatcher class-level checks), organization, family,
    # gallery, photo. Build a scope linking account + organization.
    account = insert_account!(role: :admin)
    org = insert_organization!()
    family = insert_family!(org)
    gallery = insert_gallery!(family)
    photo = insert_photo!(gallery, org)

    scope = %Ancestry.Identity.Scope{account: account, organization: org}
    {:ok, scope: scope, photo: photo}
  end

  test "build_multi/1 inserts the comment, preloads :account, computes broadcast effect",
       %{scope: scope, photo: photo} do
    cmd = CreatePhotoComment.new!(%{photo_id: photo.id, text: "wow"})
    env = Envelope.wrap(scope, cmd)

    {:ok, changes} =
      CreatePhotoCommentHandler.build_multi(env)
      |> Ancestry.Repo.transaction()

    assert %PhotoComment{text: "wow", account_id: id} = changes.photo_comment
    assert id == scope.account.id
    assert %PhotoComment{account: %Ancestry.Identity.Account{}} = changes.preloaded
    assert [{:broadcast, topic, {:comment_created, _}}] = changes.__effects__
    assert topic == "photo_comments:#{photo.id}"
  end
end
```

(The placeholder helpers `insert_account!/1`, `insert_organization!/0`, etc. must be replaced with the real factory functions found in Step 1. Do NOT hand-roll `Repo.insert/1` calls — every existing user-flow test goes through the factory.)

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/ancestry/handlers/create_photo_comment_handler_test.exs
```

- [ ] **Step 3:** Implement.

```elixir
# lib/ancestry/handlers/create_photo_comment_handler.ex
defmodule Ancestry.Handlers.CreatePhotoCommentHandler do
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
```

- [ ] **Step 4:** Run, confirm pass.

```bash
mix test test/ancestry/handlers/create_photo_comment_handler_test.exs
```

- [ ] **Step 5:** End-to-end smoke through `Bus.dispatch/2`. Add to the same test file:

```elixir
test "Bus.dispatch wires the create command end-to-end", %{scope: scope, photo: photo} do
  Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
  {:ok, cmd} = Ancestry.Commands.CreatePhotoComment.new(%{photo_id: photo.id, text: "smoke"})

  assert {:ok, %PhotoComment{text: "smoke"} = c} = Ancestry.Bus.dispatch(scope, cmd)
  assert c.account.id == scope.account.id

  assert_receive {:comment_created, %PhotoComment{text: "smoke"}}, 500

  assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
  assert row.command_module == "Ancestry.Commands.CreatePhotoComment"
  assert row.payload == %{photo_id: photo.id, text: "smoke"}
end
```

- [ ] **Step 6:** Run, confirm pass.

```bash
mix test test/ancestry/handlers/create_photo_comment_handler_test.exs
```

- [ ] **Step 7:** Commit.

```bash
mix format lib/ancestry/handlers/create_photo_comment_handler.ex test/ancestry/handlers/create_photo_comment_handler_test.exs
git add lib/ancestry/handlers/create_photo_comment_handler.ex test/ancestry/handlers/create_photo_comment_handler_test.exs
git commit -m "Add CreatePhotoComment handler with broadcast effect"
```

---

## Task 15: Rewire LiveView for `save_comment`

**Files:**
- Modify: `lib/web/live/comments/photo_comments_component.ex`
- Test: `test/user_flows/photo_comments_create_test.exs`

- [ ] **Step 1:** Inspect existing user-flow tests to copy the shape.

```bash
cat test/user_flows/CLAUDE.md
ls test/user_flows/
head -40 test/user_flows/acquaintance_person_test.exs
```

Per CLAUDE.md, the gallery route is `/org/:org_id/families/:family_id/galleries/:id` (galleries are routed by `id`, not by `photo_id`). The photo comments component is rendered inside `Web.GalleryLive.Show`, so the test navigates to the gallery and selects a photo. Mirror the existing flow tests' login + setup helpers.

- [ ] **Step 2:** Write the E2E user-flow test.

```elixir
# test/user_flows/photo_comments_create_test.exs
defmodule Web.UserFlows.PhotoCommentsCreateTest do
  use Web.ConnCase, async: false  # PubSub
  import Phoenix.LiveViewTest

  # Given a logged-in account with access to a photo in a gallery
  # When the user types a comment and submits the new-comment form
  # Then a new PhotoComment is created
  # And the comment appears in the list
  # And an audit_log row is written with the correct command_module

  setup [:setup_logged_in_account_with_photo]

  test "creates a comment via the bus", %{conn: conn, org: org, family: family, gallery: gallery, photo: photo} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    # Open the photo (selector depends on the gallery template — copy from
    # an existing user-flow test that opens a photo).
    open_photo(view, photo)

    view
    |> form("#new-comment-form", comment: %{text: "Hello"})
    |> render_submit()

    assert render(view) =~ "Hello"

    assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.CreatePhotoComment"
    assert row.payload["text"] == "Hello"
  end

  test "shows form validation error on empty submit", %{conn: conn, org: org, family: family, gallery: gallery, photo: photo} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    open_photo(view, photo)

    html =
      view
      |> form("#new-comment-form", comment: %{text: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Ancestry.Repo.all(Ancestry.Audit.Log) == []
  end

  defp setup_logged_in_account_with_photo(_) do
    # Copy the helper pattern from test/user_flows/account_management_test.exs
    # or the closest existing flow that creates account + org + family + gallery
    # + photo and logs in. Return %{conn, org, family, gallery, photo}.
    :ok
  end

  defp open_photo(view, photo) do
    # Adapt to the gallery template — look at how other tests click through to
    # a photo (e.g. clicking a phx-click element with phx-value-id={photo.id}).
    :ok
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

```bash
mix test test/user_flows/photo_comments_create_test.exs
```

- [ ] **Step 3:** Modify `lib/web/live/comments/photo_comments_component.ex` `handle_event("save_comment", ...)`:

Replace the existing `save_comment` handler with:

```elixir
def handle_event("save_comment", %{"comment" => %{"text" => text}}, socket) do
  attrs = %{photo_id: socket.assigns.photo_id, text: text}

  case Ancestry.Commands.CreatePhotoComment.new(attrs) do
    {:ok, command} ->
      socket.assigns.current_scope
      |> Ancestry.Bus.dispatch(command)
      |> handle_dispatch_result(socket)

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
  end
end

# Shared mapping for all dispatch results in this component. Add new cases
# here when handlers introduce new error shapes. Mirrors the spec's error
# table.
defp handle_dispatch_result({:ok, _result}, socket) do
  changeset = Ancestry.Comments.change_photo_comment(%Ancestry.Comments.PhotoComment{})
  {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
end

defp handle_dispatch_result({:error, :validation, changeset}, socket) do
  {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
end

defp handle_dispatch_result({:error, :unauthorized}, socket) do
  {:noreply,
   put_flash(socket, :error, gettext("You don't have permission to do that."))}
end

defp handle_dispatch_result({:error, :not_found}, socket) do
  {:noreply,
   put_flash(socket, :error, gettext("That comment no longer exists."))}
end

defp handle_dispatch_result({:error, :conflict, _term}, socket) do
  {:noreply,
   put_flash(socket, :error,
     gettext("That action conflicted with another change. Please retry."))}
end

defp handle_dispatch_result({:error, :handler, term}, socket) do
  require Logger
  Logger.error("command failed", error: inspect(term))
  {:noreply, put_flash(socket, :error, gettext("Something went wrong."))}
end
```

- [ ] **Step 4:** Run gettext extract.

```bash
mix gettext.extract --merge
```

Fill Spanish translations in `priv/gettext/es-UY/LC_MESSAGES/default.po` for the new strings.

- [ ] **Step 5:** Run the full test suite.

```bash
mix test
```

- [ ] **Step 6:** Manually exercise: `iex -S mix phx.server`, log in, post a comment, confirm it appears, then `mix execute_sql_query` (via Tidewave) or `psql` to confirm `audit_log` has a new row.

- [ ] **Step 7:** Commit.

```bash
mix format
git add lib/web/live/comments/photo_comments_component.ex test/user_flows/photo_comments_create_test.exs priv/gettext
git commit -m "Wire photo-comment creation through Ancestry.Bus"
```

---

## Task 16: `Ancestry.Commands.UpdatePhotoComment`

**Files:**
- Create: `lib/ancestry/commands/update_photo_comment.ex`
- Test: `test/ancestry/commands/update_photo_comment_test.exs`

Mirror Task 13. Fields `[:photo_comment_id, :text]`. Permission `{:update, PhotoComment}`. Primary step `:preloaded`.

- [ ] **Step 1:** Test (analogous to Task 13).
- [ ] **Step 2:** Run-fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run-pass.
- [ ] **Step 5:** Commit: `Add Ancestry.Commands.UpdatePhotoComment`.

---

## Task 17: `Ancestry.Handlers.UpdatePhotoCommentHandler`

**Files:**
- Create: `lib/ancestry/handlers/update_photo_comment_handler.ex`
- Test: `test/ancestry/handlers/update_photo_comment_handler_test.exs`

- [ ] **Step 1:** Write tests covering: success, `:not_found` for missing id, `:unauthorized` for non-owner, broadcast emitted.

- [ ] **Step 2:** Run-fail.

- [ ] **Step 3:** Implement.

```elixir
# lib/ancestry/handlers/update_photo_comment_handler.ex
defmodule Ancestry.Handlers.UpdatePhotoCommentHandler do
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
      c   -> {:ok, c}
    end
  end

  # Inline owner-or-admin check (record-level). The dispatcher already ran the
  # class-level Permit check; here we enforce the data-dependent rule.
  #
  # Do NOT call `Authorization.can?(scope, :update, PhotoComment)` inside this
  # cond — for the :editor role it returns true for ANY comment because
  # `Ancestry.Permissions` grants `all(PhotoComment)` at class level. The
  # owner restriction lives only here.
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
```

- [ ] **Step 4:** Run-pass.
- [ ] **Step 5:** Commit: `Add UpdatePhotoComment handler with owner-only authz`.

---

## Task 18: Rewire LiveView for `save_edit`

**Files:**
- Modify: `lib/web/live/comments/photo_comments_component.ex`
- Test: `test/user_flows/photo_comments_edit_test.exs`

- [ ] **Step 1:** E2E test (Given/When/Then). Cover: owner edits successfully; non-owner edit attempt fails with flash.
- [ ] **Step 2:** Run-fail.
- [ ] **Step 3:** Replace the `save_edit` handler. Use the shared `handle_dispatch_result/2` introduced in Task 15:

```elixir
def handle_event("save_edit", %{"comment" => %{"text" => text}}, socket) do
  attrs = %{photo_comment_id: socket.assigns.editing_comment_id, text: text}

  case Ancestry.Commands.UpdatePhotoComment.new(attrs) do
    {:ok, command} ->
      socket.assigns.current_scope
      |> Ancestry.Bus.dispatch(command)
      |> handle_dispatch_result(socket)
      |> clear_edit_state_on_success()

    {:error, changeset} ->
      {:noreply, assign(socket, :edit_form, to_form(changeset, as: :comment))}
  end
end

defp clear_edit_state_on_success({:noreply, socket}) do
  if socket.assigns[:editing_comment_id] do
    {:noreply,
     socket
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)}
  else
    {:noreply, socket}
  end
end
```

Note: extending `handle_dispatch_result/2` to clear edit state on `:ok` would couple the helper to update-specific concerns. Keeping the post-step here is cleaner.
- [ ] **Step 4:** Run-pass; gettext extract+merge if new strings.
- [ ] **Step 5:** Commit: `Wire photo-comment edit through Ancestry.Bus`.

---

## Task 19: `Ancestry.Commands.DeletePhotoComment`

**Files:**
- Create: `lib/ancestry/commands/delete_photo_comment.ex`
- Test: `test/ancestry/commands/delete_photo_comment_test.exs`

Mirror Task 13. Fields `[:photo_comment_id]`. Permission `{:delete, PhotoComment}`. Primary step `:photo_comment` (the deleted struct).

- [ ] **Step 1–5:** TDD per Task 13 pattern. Commit: `Add Ancestry.Commands.DeletePhotoComment`.

---

## Task 20: `Ancestry.Handlers.DeletePhotoCommentHandler`

**Files:**
- Create: `lib/ancestry/handlers/delete_photo_comment_handler.ex`
- Test: `test/ancestry/handlers/delete_photo_comment_handler_test.exs`

- [ ] **Step 1:** Tests: success (owner), success (admin deleting other's comment), `:not_found`, `:unauthorized` for non-owner non-admin, broadcast emitted.
- [ ] **Step 2:** Run-fail.
- [ ] **Step 3:** Implement. Identical shape to `UpdatePhotoCommentHandler` but:
  - `Multi.delete/3` instead of `Multi.update/3`.
  - Preload runs on the loaded record **before** delete so the broadcast carries `:account`.
  - `:authorize` step allows admin override (already in the inline check above).

```elixir
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
    c   -> {:ok, Repo.preload(c, :account)}
  end
end

defp compute_effects(_repo, %{photo_comment: c, load: loaded}) do
  {:ok,
   [
     {:broadcast, "photo_comments:#{c.photo_id}", {:comment_deleted, loaded}}
   ]}
end
```

- [ ] **Step 4:** Run-pass.
- [ ] **Step 5:** Commit: `Add DeletePhotoComment handler with admin override`.

---

## Task 21: Rewire LiveView for `delete_comment`, drop inline admin check

**Files:**
- Modify: `lib/web/live/comments/photo_comments_component.ex`
- Test: `test/user_flows/photo_comments_delete_test.exs`

- [ ] **Step 1:** E2E test: owner deletes; admin deletes other's; non-owner non-admin gets flash.
- [ ] **Step 2:** Run-fail.
- [ ] **Step 3:** Replace `delete_comment` handler:

```elixir
def handle_event("delete_comment", %{"id" => id}, socket) do
  command =
    Ancestry.Commands.DeletePhotoComment.new!(%{
      photo_comment_id: String.to_integer(id)
    })

  socket.assigns.current_scope
  |> Ancestry.Bus.dispatch(command)
  |> handle_dispatch_result(socket)
end
```

Remove `defp can_delete?` if it's no longer referenced after this rewire.

- [ ] **Step 4:** Run-pass; gettext.
- [ ] **Step 5:** Commit: `Wire photo-comment delete through Ancestry.Bus, remove inline admin check`.

---

## Task 22: Strip mutations from `Ancestry.Comments`

**Files:**
- Modify: `lib/ancestry/comments.ex`

Goal: `Ancestry.Comments` exports only queries. The user's WIP already deleted `create_photo_comment/3`. This task removes `update_photo_comment/2` and `delete_photo_comment/1` if still present.

- [ ] **Step 1:** Inspect current state.

```bash
grep -n "def " lib/ancestry/comments.ex
```

- [ ] **Step 2:** Find every callsite of the mutation functions BEFORE deleting them.

```bash
grep -rn "Comments.create_photo_comment\|Comments.update_photo_comment\|Comments.delete_photo_comment" lib/ test/
```

Expected after Tasks 15/18/21: zero LiveView callsites. Any test that still calls these must be migrated to dispatch through `Ancestry.Bus` or to use the schema directly. Do this migration in this task before the deletion.

- [ ] **Step 3:** Delete `update_photo_comment/2` and `delete_photo_comment/1` from `lib/ancestry/comments.ex`. Confirm only queries remain (`list_photo_comments/1`, `get_photo_comment!/1`, `change_photo_comment/2`).

- [ ] **Step 4:** `mix compile --warnings-as-errors` and `mix test`. Fix any breakage from missed callsites identified in Step 2.

- [ ] **Step 5:** Commit: `Strip mutations from Ancestry.Comments (queries only)`.

---

## Task 23: Final verification

- [ ] **Step 1:** Run `mix precommit`.

```bash
mix precommit
```

Fix any compile/format/test failures before continuing.

- [ ] **Step 2:** Manual smoke in dev.

```bash
iex -S mix phx.server
```

- Log in.
- Open a photo with comments.
- Create, edit, delete a comment. Each operation should appear instantly via PubSub.
- Inspect `audit_log` via Tidewave (`execute_sql_query`):

```sql
SELECT command_module, payload, account_email, organization_name, inserted_at
FROM audit_log
ORDER BY inserted_at DESC
LIMIT 10;
```

Expected: 3 rows (create, update, delete) for the test session.

- [ ] **Step 3:** Confirm telemetry emission. In IEx:

```elixir
:telemetry.attach(
  "watch-bus",
  [:ancestry, :bus, :dispatch, :stop],
  fn _, m, meta, _ ->
    IO.inspect({m, Map.take(meta, [:command_module, :outcome, :error_tag, :command_id])})
  end,
  nil
)
```

Trigger an action; expect a printed event.

- [ ] **Step 4:** Verify Logger metadata propagation. Hit any LiveView event and confirm logs include `request_id=req-...` and `command_id=cmd-...` (use `mix test --trace` or `iex` log inspection).

- [ ] **Step 5:** Final commit (no-op or summary).

```bash
git log --oneline commands ^main
```

Confirm the branch contains an orderly sequence of small commits, each green.

---

## Open follow-ups (NOT in this plan)

- Auditing failures (authz/validation) into a separate sink.
- Migrating other contexts (Galleries, Families, Identity, …) through `Ancestry.Bus`.
- Entity external ids (`acc-<sha1>`, etc.) and URL changes.
- Rate limiting / replay protection keyed on `command_id`.
- Promoting the inline owner check into Permit clauses if the installed Permit version supports record-level conditions.

---

## Notes for the executing engineer

- Read `docs/plans/2026-05-07-command-handler-foundation.md` (the spec) before starting Task 1.
- The user prefers terse, mechanical communication. Skip pleasantries.
- Use Tidewave (`get_ecto_schemas`, `get_source_location`, `project_eval`, `execute_sql_query`, `get_logs`) before guessing about runtime state. Do not invent module APIs or schema fields.
- E2E tests must follow `test/user_flows/CLAUDE.md`: Given/When/Then comments, snake_case `_test.exs` files, exercise rendered templates with real data.
- Use `pgettext/2` for gendered Spanish strings (none expected in this refactor) and `gettext/1` otherwise. Run `mix gettext.extract --merge` after adding strings; fill `priv/gettext/es-UY/LC_MESSAGES/default.po`.
- After every code-touching task, `mix compile --warnings-as-errors` must pass before the commit step.
- Final task runs `mix precommit`. Do not skip it.
