# Command/Handler Foundation — Photo Comments Migration

**Status:** Design — pending implementation plan
**Date:** 2026-05-07
**Branch:** `commands`
**Predecessor:** staged WIP under `lib/framework/`, `lib/ancestry/commands/`, `lib/ancestry/handlers/`

## Goal

Introduce a command/handler dispatch layer for state-mutating operations as the foundation for an audit log. Migrate photo comment mutations (create / update / delete) to validate the pattern. Defer broader migration.

## Motivation

The future audit log requires a single choke point that can capture (who, when, which org, which command, with what input) for every state mutation. Today, mutations are scattered across context modules (`Ancestry.Comments`, `Ancestry.Galleries`, `Ancestry.Families`, …). Wrapping each callsite manually is fragile. A bus + command/handler split makes every mutation a first-class value, dispatched through a single function — natural place to attach audit, authz, telemetry, and post-commit side effects.

## Scope

### In scope

1. `Ancestry.Bus` dispatcher with `Command`, `Handler`, `Envelope` behaviours.
2. `Ancestry.Prefixes` registry module for all external/exposed id prefixes (app-wide; lives outside the bus namespace because prefixes are not bus-specific).
3. `Web.PrefixedRequestIdPlug` replacing `Plug.RequestId`.
4. `audit_log` table + `Ancestry.Audit.Log` schema + `Ancestry.Audit.Serializer` (redaction).
5. Three commands and three handlers for photo comments: create, update, delete.
6. `Ancestry.Comments` reduced to query-only.
7. `Web.Comments.PhotoCommentsComponent` rewired through the bus.
8. Move owner-vs-admin photo-comment authz from LiveView into `Ancestry.Permissions`.
9. Delete `lib/framework/` (staged WIP) — replaced by `lib/ancestry/bus/`.

### Out of scope

- Adding `external_id` columns to entities (Account, Organization, Photo, etc.).
- Replacing numeric ids in URLs.
- Migrating mutations of other contexts (Galleries, Families, Identity, …).
- `commanded` / event sourcing.
- Auditing failures (validation/authz/exception). Failures flow through `:telemetry` and `Logger` only.

## Decisions (locked)

| Concern | Decision |
|---|---|
| Validation | Hybrid: command-level changeset (`new/1`) + entity changeset (at insert/update). |
| Authorization | Dispatcher-level via Permit on `(action, resource)`. Fine-grained, data-dependent rules live in handler Multi step returning `{:error, :unauthorized}`. |
| Envelope | `%Envelope{scope, command_id, correlation_id, issued_at, command}`. Wrapped, not embedded. |
| Dispatcher | `Ancestry.Bus.dispatch(scope, command, opts)` and `Ancestry.Bus.dispatch_envelope(envelope)`. |
| Audit timing | In-transaction `Multi.insert` step. Successes only land in `audit_log`. |
| Audit failure path | `:telemetry` events + `Logger` metadata; no DB row. |
| Side effects | Handlers append `Multi.put(:__effects__, [...])`. Dispatcher fires after `Repo.transaction/1` succeeds. |
| Migration scope | All photo comment mutations. Reads stay in `Ancestry.Comments`. |
| Namespace | `Ancestry.Bus.{Command, Handler, Envelope}`. |
| Layout | Flat: `lib/ancestry/commands/`, `lib/ancestry/handlers/`. |
| Errors | `{:ok, _}` / `{:error, :unauthorized}` / `{:error, :validation, cs}` / `{:error, :not_found}` / `{:error, :conflict, _}` / `{:error, :handler, _}`. |
| ID format | `<prefix>-<uuid>`. Prefixes 3–4 chars, registered in `Ancestry.Prefixes`. |
| Audit FKs | None. Denormalized snapshots of account/organization names + emails. OLAP-oriented. |
| Audit table name | `audit_log`. |
| Request id | `Web.PrefixedRequestIdPlug` always generates `req-<uuid>`. Inbound `x-request-id` preserved as `Logger.metadata[:inbound_request_id]`. |

## Module layout

```
lib/ancestry/
  bus.ex                      # Ancestry.Bus
  bus/
    command.ex                # behaviour
    handler.ex                # behaviour
    envelope.ex
  prefixes.ex                 # app-wide id prefix registry
  audit/
    log.ex                    # Ecto schema for audit_log
    serializer.ex             # serialize(command) → redacted map
  commands/
    create_photo_comment.ex
    update_photo_comment.ex
    delete_photo_comment.ex
  handlers/
    create_photo_comment_handler.ex
    update_photo_comment_handler.ex
    delete_photo_comment_handler.ex
  comments.ex                 # QUERIES ONLY
  comments/photo_comment.ex   # unchanged

lib/web/
  plugs/prefixed_request_id_plug.ex
  endpoint.ex                 # swap Plug.RequestId → PrefixedRequestIdPlug
  live/comments/photo_comments_component.ex   # rewired

priv/repo/migrations/
  YYYYMMDDHHMMSS_create_audit_log.exs

lib/framework/                # DELETED
lib/ancestry/commands/create_photo_comment.ex     # REWRITTEN
lib/ancestry/handlers/create_photo_comment_handler.ex  # REWRITTEN
```

## `Ancestry.Prefixes`

```elixir
defmodule Ancestry.Prefixes do
  @moduledoc """
  Single source of truth for prefixes used in external/exposed ids
  throughout the application. Format: `<prefix>-<uuid>`.

  Add an entry whenever introducing a new prefixed id. Compile-time
  checks enforce uniqueness and length (3–4 chars).
  """

  @prefixes %{
    command:      "cmd",   # wired now
    request:      "req",   # wired now
    account:      "acc",   # reserved
    organization: "org",   # reserved
    photo:        "pho",   # reserved
    gallery:      "gal",   # reserved
    family:       "fam",   # reserved
    person:       "per",   # reserved
    comment:      "com"    # reserved
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
    if prefix in Map.values(@prefixes), do: {prefix, rest},
      else: raise(ArgumentError, "unknown id prefix: #{inspect(prefix)} in #{inspect(id)}")
  end

  @spec known_kinds() :: [atom()]
  def known_kinds, do: Map.keys(@prefixes)
end
```

## `Ancestry.Bus.Envelope`

```elixir
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

  def wrap(scope, command, opts \\ []) do
    %__MODULE__{
      scope: scope,
      command: command,
      command_id: Prefixes.generate(:command),
      correlation_id: opts[:correlation_id] || current_request_id() || Prefixes.generate(:request),
      issued_at: DateTime.utc_now()
    }
  end

  defp current_request_id do
    Logger.metadata()[:request_id]
  end
end
```

## `Ancestry.Bus.Command`

```elixir
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

## `Ancestry.Bus.Handler`

```elixir
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

Handlers do **not** call `Repo.transaction/1`. They build a Multi and return it. Side effects are deposited under the `:__effects__` key as a list of plain tuples that the dispatcher will fire after commit. The handler computes them in a `Multi.run/3` step (so prior steps' results are accessible):

```elixir
|> Multi.run(:__effects__, fn _repo, %{photo_comment: c} ->
  {:ok,
   [
     {:broadcast, "photo_comments:#{c.photo_id}", {:comment_created, c}}
   ]}
end)
```

**Locked effect shape.** Each effect is a tuple matched by `Bus.run_effect/1`:

| Tuple | Action |
|---|---|
| `{:broadcast, topic, message}` | `Phoenix.PubSub.broadcast(Ancestry.PubSub, topic, message)` |

New effect kinds are added by extending `Bus.run_effect/1` and documenting the tuple here. Functions are **not** allowed in `:__effects__` — only literal tuples computed inside Multi steps.

The dispatcher fires effects after commit, in list order. Effect failures are logged but do not roll back the transaction (it has already committed).

## `Ancestry.Bus`

```elixir
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

    # Class-level pre-check. For resources whose Permit clauses are entirely
    # record-conditioned (e.g. owner-only update on PhotoComment), this acts
    # as a no-op gate: it passes if any record could be authorized, then the
    # handler's :authorize Multi step does the actual record-level check.
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
      |> Multi.insert(:__audit__, fn _changes -> Audit.Log.changeset_from(env) end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        Enum.each(changes[:__effects__] || [], &run_effect/1)
        {:ok, Map.fetch!(changes, module.primary_step())}

      {:error, _step, %Ecto.Changeset{} = cs, _}    -> {:error, :validation, cs}
      {:error, _step, :not_found, _}                -> {:error, :not_found}
      {:error, _step, {:not_found, _}, _}           -> {:error, :not_found}
      {:error, _step, :unauthorized, _}             -> {:error, :unauthorized}
      {:error, _step, {:conflict, t}, _}            -> {:error, :conflict, t}
      {:error, _step, other, _}                     -> {:error, :handler, other}
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

  defp outcome_metadata({:ok, _}),                     do: %{outcome: :ok, error_tag: nil}
  defp outcome_metadata({:error, tag}),                do: %{outcome: :error, error_tag: tag}
  defp outcome_metadata({:error, tag, _}),             do: %{outcome: :error, error_tag: tag}

  defp scope_org_id(%{organization: %{id: id}}), do: id
  defp scope_org_id(_),                          do: nil
end
```

## `audit_log` migration

```elixir
defmodule Ancestry.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def change do
    create table(:audit_log) do
      add :command_id,        :string,  null: false   # "cmd-<uuid>"
      add :correlation_id,    :string,  null: false   # "req-<uuid>"
      add :command_module,    :string,  null: false
      add :account_id,        :bigint,  null: false   # denormalized; no FK
      add :account_name,      :string,  null: true    # Account.name is nullable in source schema
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

## `Ancestry.Audit.Log`

```elixir
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

  def changeset_from(envelope) do
    %__MODULE__{}
    |> cast(attrs_from(envelope), [
      :command_id, :correlation_id, :command_module,
      :account_id, :account_name, :account_email,
      :organization_id, :organization_name, :payload
    ])
    |> validate_required([
      :command_id, :correlation_id, :command_module,
      :account_id, :account_email, :payload
    ])
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

  defp org_id(%{organization: %{id: id}}),     do: id
  defp org_id(_),                              do: nil
  defp org_name(%{organization: %{name: n}}),  do: n
  defp org_name(_),                            do: nil
end
```

## `Ancestry.Audit.Serializer`

```elixir
defmodule Ancestry.Audit.Serializer do
  @doc """
  Serializes a command struct to a map suitable for jsonb storage.
  Replaces redacted fields with "[redacted]" and binary blobs with
  "binary-blob". Drops the :__struct__ key (the command module is
  stored as a separate column).
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

## Photo comment commands

### `Ancestry.Commands.CreatePhotoComment`

```elixir
defmodule Ancestry.Commands.CreatePhotoComment do
  use Ancestry.Bus.Command
  alias Ancestry.Comments.PhotoComment

  @enforce_keys [:photo_id, :text]
  defstruct [:photo_id, :text]

  @types %{photo_id: :integer, text: :string}

  @impl true
  def new(attrs) do
    {%{}, @types}
    |> Ecto.Changeset.cast(attrs, Map.keys(@types))
    |> Ecto.Changeset.validate_required([:photo_id, :text])
    |> Ecto.Changeset.validate_length(:text, max: 5000)
    |> case do
      %{valid?: true} = cs -> {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))}
      cs                   -> {:error, %{cs | action: :validate}}
    end
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

### `Ancestry.Commands.UpdatePhotoComment`

Fields `[:photo_comment_id, :text]`, permission `{:update, PhotoComment}`, primary `:preloaded` (handler reloads with `:account` after update so the LiveView receives the same shape as create).

### `Ancestry.Commands.DeletePhotoComment`

Fields `[:photo_comment_id]`, permission `{:delete, PhotoComment}`, primary `:photo_comment` (the deleted struct, preloaded before delete so the LiveView can broadcast it).

## Photo comment handlers

### `Ancestry.Handlers.CreatePhotoCommentHandler`

```elixir
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

**Primary step.** `CreatePhotoComment.primary_step/0` returns `:preloaded` (the value the LiveView will receive — preloaded with `:account`).

### Update / Delete handlers

UpdatePhotoCommentHandler shape (real Multi calls; no pseudocode):

```elixir
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

defp authorize(_repo, %{scope: scope, load: comment}) do
  if Authorization.can?(scope, :update, comment), do: {:ok, :ok}, else: {:error, :unauthorized}
end

defp update_changeset(%{load: comment, command: cmd}),
  do: PhotoComment.changeset(comment, %{text: cmd.text})

defp preload_account(_repo, %{photo_comment: c}),
  do: {:ok, Repo.preload(c, :account)}

defp compute_effects(_repo, %{preloaded: c}) do
  {:ok, [{:broadcast, "photo_comments:#{c.photo_id}", {:comment_updated, c}}]}
end
```

DeletePhotoCommentHandler is identical except: `Multi.delete(:photo_comment, ...)` and the effect is `{:comment_deleted, c}`. Preload runs **before** delete so the broadcast carries the loaded `:account`.

**Permit clauses for owner-or-admin.**

The owner-vs-admin rule moves from the LiveView into `Ancestry.Permissions`. Existing role-based clauses are preserved; owner-conditioned clauses are added.

```elixir
# Sketch — confirm exact DSL against Permit docs during implementation.
def can(%Scope{account: %Account{role: role}} = _scope) when role in [:editor, :viewer] do
  permit()
  |> read(PhotoComment)
  |> create(PhotoComment)
  |> update(PhotoComment,
       fn %Scope{account: a}, %PhotoComment{account_id: aid} -> a.id == aid end)
  |> delete(PhotoComment,
       fn %Scope{account: a}, %PhotoComment{account_id: aid} -> a.id == aid end)
end
```

Admin clause (`role: :admin`) keeps `all(PhotoComment)` and so passes record-level checks unconditionally.

Permit's record-level support (3-arity `update/3`, `delete/3`) must be confirmed against the version of `:permit` in `mix.lock`. If the installed version does not support a function-as-condition, fallback: encode the rule inline in the handler's `:authorize` step using `account_id == scope.account.id or scope.account.role == :admin` and add a TODO to upstream into Permit when supported.

**Authorization flow for update/delete:**

1. Dispatcher: coarse `Authorization.can?(scope, :update, PhotoComment)`. Class-level — passes if any record-level rule could grant access.
2. Handler `:load` step: fetch the row.
3. Handler `:authorize` step: `Authorization.can?(scope, :update, comment)` — record-level. Short-circuits with `{:error, :unauthorized}` on denial.
4. Handler `:photo_comment` step: `Multi.update`/`Multi.delete`.

## `Ancestry.Comments` (queries only)

```elixir
defmodule Ancestry.Comments do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Comments.PhotoComment

  def list_photo_comments(photo_id) do
    Repo.all(
      from c in PhotoComment,
        where: c.photo_id == ^photo_id,
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:account]
    )
  end

  def get_photo_comment!(id), do: Repo.get!(PhotoComment, id) |> Repo.preload(:account)

  def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}),
    do: PhotoComment.changeset(comment, attrs)
end
```

`create_photo_comment/3`, `update_photo_comment/2`, `delete_photo_comment/1` are deleted.

## `Web.PrefixedRequestIdPlug`

```elixir
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

`Web.Endpoint` swaps `plug Plug.RequestId` for `plug Web.PrefixedRequestIdPlug`.

## LiveView changes (`Web.Comments.PhotoCommentsComponent`)

- `save_comment` event: `CreatePhotoComment.new(%{...})`. On `{:error, cs}` re-render form. On `{:ok, cmd}` call `Ancestry.Bus.dispatch(scope, cmd)`.
- `save_edit` event: `UpdatePhotoComment.new(...)` then `Bus.dispatch/2`.
- `delete_comment` event: `DeletePhotoComment.new!(...)` then `Bus.dispatch/2`. Hand-rolled `account.role == :admin` check is removed.
- `select_comment`, `edit_comment`, `cancel_edit` (intent-only) stay as-is.
- The `:comment_created` / `:comment_updated` / `:comment_deleted` PubSub messages are still emitted, but now from handler effects via the dispatcher.

### Error mapping

Every LiveView callsite that pattern-matches `Bus.dispatch/2`'s result MUST cover the full taxonomy. Default mapping:

| Result | LiveView action |
|---|---|
| `{:ok, result}` | Reset form / clear edit state. PubSub broadcast (already in handler effects) updates the stream. |
| `{:error, :validation, cs}` | Re-render form with the changeset. No flash. |
| `{:error, :unauthorized}` | `put_flash(:error, gettext("You don't have permission to do that."))`. No state change. |
| `{:error, :not_found}` | `put_flash(:error, gettext("That comment no longer exists."))`. Optionally re-fetch the list. |
| `{:error, :conflict, _term}` | `put_flash(:error, gettext("That action conflicted with another change. Please retry."))`. |
| `{:error, :handler, term}` | `Logger.error("command failed", error: inspect(term))`; `put_flash(:error, gettext("Something went wrong."))`. |

All new user-facing strings flow through `gettext/1` (or `pgettext/2` for gendered cases). After adding strings, run `mix gettext.extract --merge` and fill Spanish translations in `priv/gettext/es-UY/LC_MESSAGES/*.po` per CLAUDE.md.

### Correlation in LiveView events

`Web.PrefixedRequestIdPlug` sets `Logger.metadata[:request_id]` on the initial HTTP request that mounts the LiveView, but **the LiveView process does not inherit Logger metadata across the WebSocket boundary** by default. As a result, `Bus.dispatch/2` invoked from a `handle_event/3` callback will fall through `Envelope.wrap/3`'s `current_request_id/0` lookup and allocate a fresh `req-<uuid>` per event.

This is the v1 behavior and is acceptable: each user action becomes its own correlation chain. Linking the chain back to the originating HTTP request is a follow-up (would require setting `Logger.metadata` in `mount/3` and `handle_event/3` from `socket.assigns` populated by an `on_mount` hook).

## Telemetry + Logger

- Dispatcher wraps `do_dispatch/2` in `:telemetry.span([:ancestry, :bus, :dispatch], metadata, fun)`.
- Metadata: `command_id`, `correlation_id`, `command_module`, `account_id`, `organization_id`, `outcome`, `error_tag`.
- Logger metadata is set inside the span so child logs inherit the ids.
- Standard Phoenix log config picks up `request_id`, `correlation_id`, etc.

## Tests

### Unit per handler
- Build envelope manually, call `Handler.build_multi/1`, run inside `Repo.transaction/1`, assert changes map.
- Cover all Multi steps including failure paths (e.g., not_found, unauthorized).

### Integration per dispatcher
- Authz denial → `{:error, :unauthorized}`, no `audit_log` row.
- Validation failure (`new/1`) → `{:error, :validation, cs}` before dispatch, no row.
- Validation failure (entity changeset inside Multi) → `{:error, :validation, cs}`, no row.
- Success → `{:ok, _}`, exactly one `audit_log` row with redacted payload, command_id present, correlation_id matches Logger.metadata.

### E2E user flows (`test/user_flows/`)
- `photo_comments_create_test.exs`, `photo_comments_edit_test.exs`, `photo_comments_delete_test.exs` (the project convention is `_test.exs` suffix; existing examples include `account_management_test.exs`, `acquaintance_person_test.exs`).
- Follow `test/user_flows/CLAUDE.md` conventions for Given/When/Then structure.
- Cover: success path, validation error (empty text), authz error (non-owner edit/delete by non-admin), admin override on delete.

## Migration risks

1. `lib/framework/` exists in the staged WIP. Rename and rewrite must not leave dangling aliases. Recommend `git rm` of `lib/framework/` before writing the new modules.
2. `Permit` rules for owner-vs-admin must be added before LiveView removes its inline check, or delete will silently 200 for non-owners.
3. PubSub topic strings must match exactly across handler, LiveView, and tests (`"photo_comments:#{photo_id}"`).
4. `Logger.metadata[:request_id]` is set by the plug for HTTP requests but not for LiveView reconnects. Acceptable for v1: dispatcher falls back to a fresh `req-<uuid>` if absent.
5. Existing data has no audit rows. Backfill is not required; audit starts at deploy time.
6. `account.name` is nullable in the schema (`add :name, :string` with no `null: false`). Resolved: `audit_log.account_name` is `null: true` and `validate_required` excludes it. No coercion needed. `account_email` is required by `phx.gen.auth` and stays `null: false`.

## Open follow-ups (not blocking this refactor)

- Auditing failures (authz/validation) into a separate table or sink (currently telemetry/logger only).
- Migrating other contexts (Galleries, Families, Identity, …) to commands.
- Entity external ids (`acc-<sha1>`, etc.) and URL changes.
- Rate limiting / replay protection keyed on `command_id`.
- Linking `audit_log` rows to actual rows (e.g., adding `result_external_id` once entities have external ids).

## Verification

`mix precommit` runs cleanly (compile, format, tests).
E2E flows in `test/user_flows/photo_comments_*.exs` pass.
Manually exercise create / edit / delete in dev, observe `audit_log` rows accumulating with redacted payloads, observe `:telemetry` events in IEx via a temporary handler.
