# Galleries Bus Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate every state-mutating operation in `Ancestry.Galleries` to dispatch through `Ancestry.Bus`. Six new commands cover gallery + photo + tag CRUD. The context drops to queries-only. Worker writes stay direct.

**Architecture:** Handlers expose `def handle(envelope)`, internally building an `Ecto.Multi` via the new `Ancestry.Bus.Step` DSL and running it with `Repo.transaction/1`. The dispatcher classifies the result, fires post-commit `:effects`, returns `{:ok, primary} | {:error, tag, ...}`. Story-driven step names, no inline lambdas, split insert/update from preload.

**Tech Stack:** Elixir 1.19, Phoenix 1.8 LiveView, `Ecto.Multi`, Permit 0.3.3, Phoenix.PubSub, Oban, Waffle, Postgres, ExUnit.

**Spec:** `docs/plans/2026-05-08-galleries-bus-migration.md`. Read it before starting.

**Branch:** `commands` (continuation of the photo-comment migration). All commits land directly on this branch — no PRs.

**Conventions:**
- TDD per task: write test → run → fail → implement → run → pass → commit.
- `mix format` before each commit.
- `mix compile --warnings-as-errors` must pass before each commit.
- Final phase runs `mix precommit`.
- Commit messages follow recent log style (`Add ...`, `Refactor ...`, `Rename ...`).

---

## Phase 0 — Foundation cleanup

Goal: reshape the existing Bus + comment handlers to the locked architecture before any new gallery work. Behavior preserved end-to-end.

---

### Task P0.1: Rename `Ancestry.Workers.ProcessPhotoJob` → `Ancestry.Workers.TransformAndStorePhoto`

**Files:**
- Move: `lib/ancestry/workers/process_photo_job.ex` → `lib/ancestry/workers/transform_and_store_photo.ex`
- Modify: callsites in `lib/web/live/gallery_live/show.ex`, `lib/ancestry/galleries.ex`
- Modify: any test referencing the worker module

- [ ] **Step 1: Find all references**

```bash
grep -rln "ProcessPhotoJob" lib/ test/
```

- [ ] **Step 2: Rename file + module**

```bash
git mv lib/ancestry/workers/process_photo_job.ex lib/ancestry/workers/transform_and_store_photo.ex
```

Edit the moved file: rename `defmodule Ancestry.Workers.ProcessPhotoJob do` → `defmodule Ancestry.Workers.TransformAndStorePhoto do`.

- [ ] **Step 3: Update all callsites**

For each file from Step 1, replace `Ancestry.Workers.ProcessPhotoJob` with `Ancestry.Workers.TransformAndStorePhoto` and any aliased forms (`alias Ancestry.Workers.ProcessPhotoJob` → `alias Ancestry.Workers.TransformAndStorePhoto`).

- [ ] **Step 4: Verify compile + tests**

```bash
mix compile --warnings-as-errors
mix test
```

Expected: clean compile, all tests pass.

- [ ] **Step 5: Commit**

```bash
mix format lib/ancestry/workers/transform_and_store_photo.ex
git add -A
git commit -m "Rename ProcessPhotoJob worker to TransformAndStorePhoto"
```

---

### Task P0.2: Rename `Ancestry.Commands.CreatePhotoComment` → `AddCommentToPhoto`

**Files:**
- Move: `lib/ancestry/commands/create_photo_comment.ex` → `lib/ancestry/commands/add_comment_to_photo.ex`
- Move: `lib/ancestry/handlers/create_photo_comment_handler.ex` → `lib/ancestry/handlers/add_comment_to_photo_handler.ex`
- Move: `test/ancestry/commands/create_photo_comment_test.exs` → `test/ancestry/commands/add_comment_to_photo_test.exs`
- Move: `test/ancestry/handlers/create_photo_comment_handler_test.exs` → `test/ancestry/handlers/add_comment_to_photo_handler_test.exs`
- Modify: `lib/web/live/comments/photo_comments_component.ex`, `test/user_flows/photo_comments_create_test.exs`, `test/web/live/comments/photo_comments_component_test.exs`

- [ ] **Step 1: Find all references**

```bash
grep -rln "CreatePhotoComment\|create_photo_comment" lib/ test/
```

Note: `Ancestry.Comments.create_photo_comment/3` was already removed in the prior migration — only the command/handler module names remain.

- [ ] **Step 2: Rename files**

```bash
git mv lib/ancestry/commands/create_photo_comment.ex lib/ancestry/commands/add_comment_to_photo.ex
git mv lib/ancestry/handlers/create_photo_comment_handler.ex lib/ancestry/handlers/add_comment_to_photo_handler.ex
git mv test/ancestry/commands/create_photo_comment_test.exs test/ancestry/commands/add_comment_to_photo_test.exs
git mv test/ancestry/handlers/create_photo_comment_handler_test.exs test/ancestry/handlers/add_comment_to_photo_handler_test.exs
```

- [ ] **Step 3: Update module names + references**

In each moved file: replace `CreatePhotoComment` with `AddCommentToPhoto` (commands) and `CreatePhotoCommentHandler` with `AddCommentToPhotoHandler` (handlers). Update `handled_by/0` in the command. Update `defmodule`, alias references, and test module names.

In `lib/web/live/comments/photo_comments_component.ex`: `Ancestry.Commands.CreatePhotoComment.new/1` → `Ancestry.Commands.AddCommentToPhoto.new/1`.

In `test/user_flows/photo_comments_create_test.exs`: update `command_module` string assertion: `"Ancestry.Commands.CreatePhotoComment"` → `"Ancestry.Commands.AddCommentToPhoto"`.

- [ ] **Step 4: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

- [ ] **Step 5: Commit**

```bash
mix format
git add -A
git commit -m "Rename CreatePhotoComment to AddCommentToPhoto"
```

---

### Task P0.3: Rename `Ancestry.Commands.DeletePhotoComment` → `RemoveCommentFromPhoto`

**Files:** mirror Task P0.2 substituting `Delete` → `Remove`, `Create` → `Add`, etc.

- [ ] **Step 1: Find references**

```bash
grep -rln "DeletePhotoComment\|delete_photo_comment" lib/ test/
```

- [ ] **Step 2: Rename files**

```bash
git mv lib/ancestry/commands/delete_photo_comment.ex lib/ancestry/commands/remove_comment_from_photo.ex
git mv lib/ancestry/handlers/delete_photo_comment_handler.ex lib/ancestry/handlers/remove_comment_from_photo_handler.ex
```

If test files exist with the old names, `git mv` them too:
```bash
git mv test/ancestry/commands/delete_photo_comment_test.exs test/ancestry/commands/remove_comment_from_photo_test.exs 2>/dev/null || true
git mv test/ancestry/handlers/delete_photo_comment_handler_test.exs test/ancestry/handlers/remove_comment_from_photo_handler_test.exs 2>/dev/null || true
```

- [ ] **Step 3: Update modules + references**

Replace `DeletePhotoComment` with `RemoveCommentFromPhoto` (and `Handler` suffixes likewise). Update `lib/web/live/comments/photo_comments_component.ex`, user-flow tests' `command_module` assertion strings (`"Ancestry.Commands.DeletePhotoComment"` → `"Ancestry.Commands.RemoveCommentFromPhoto"`).

- [ ] **Step 4: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

- [ ] **Step 5: Commit**

```bash
mix format
git add -A
git commit -m "Rename DeletePhotoComment to RemoveCommentFromPhoto"
```

---

### Task P0.4: Create `Web.BusUI` shared helper

Promote the duplicated `handle_dispatch_result/2` from `PhotoCommentsComponent` into a shared module auto-imported into all LiveViews + LiveComponents.

**Files:**
- Create: `lib/web/bus_ui.ex`
- Modify: `lib/web.ex` (auto-import in `live_view`/`live_component` quotes)
- Modify: `lib/web/live/comments/photo_comments_component.ex` (remove local defps)
- Test: `test/web/bus_ui_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/web/bus_ui_test.exs
defmodule Web.BusUITest do
  use Web.ConnCase, async: true

  alias Phoenix.LiveView.Socket
  import Web.BusUI

  test "{:ok, _} returns {:noreply, socket} unchanged" do
    socket = %Socket{}
    assert {:noreply, ^socket} = handle_dispatch_result({:ok, :anything}, socket)
  end

  test "{:error, :validation, changeset} assigns the form" do
    socket = %Socket{assigns: %{__changed__: %{}}}
    cs = Ecto.Changeset.change({%{}, %{}})
    assert {:noreply, %Socket{assigns: %{form: %Phoenix.HTML.Form{}}}} =
             handle_dispatch_result({:error, :validation, cs}, socket)
  end

  test "{:error, :unauthorized} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}
    assert {:noreply, %Socket{assigns: %{flash: %{"error" => msg}}}} =
             handle_dispatch_result({:error, :unauthorized}, socket)

    assert msg =~ "permission"
  end

  test "{:error, :not_found} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}
    assert {:noreply, %Socket{assigns: %{flash: %{"error" => _}}}} =
             handle_dispatch_result({:error, :not_found}, socket)
  end

  test "{:error, :conflict, _} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}
    assert {:noreply, %Socket{}} =
             handle_dispatch_result({:error, :conflict, :stale}, socket)
  end

  test "{:error, :handler, _} sets a flash and logs" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}
    assert {:noreply, %Socket{}} =
             handle_dispatch_result({:error, :handler, :boom}, socket)
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```bash
mix test test/web/bus_ui_test.exs
```

Expected: `Web.BusUI is undefined`.

- [ ] **Step 3: Implement `Web.BusUI`**

```elixir
# lib/web/bus_ui.ex
defmodule Web.BusUI do
  @moduledoc """
  Shared LiveView helper for routing `Ancestry.Bus.dispatch/2` results
  through the standard error taxonomy.
  """

  use Gettext, backend: Web.Gettext
  alias Phoenix.Component
  alias Phoenix.LiveView

  def handle_dispatch_result({:ok, _result}, socket), do: {:noreply, socket}

  def handle_dispatch_result({:error, :validation, changeset}, socket),
    do: {:noreply, LiveView.assign(socket, :form, Component.to_form(changeset))}

  def handle_dispatch_result({:error, :unauthorized}, socket),
    do:
      {:noreply,
       LiveView.put_flash(socket, :error, gettext("You don't have permission to do that."))}

  def handle_dispatch_result({:error, :not_found}, socket),
    do: {:noreply, LiveView.put_flash(socket, :error, gettext("That item no longer exists."))}

  def handle_dispatch_result({:error, :conflict, _term}, socket),
    do:
      {:noreply,
       LiveView.put_flash(
         socket,
         :error,
         gettext("That action conflicted with another change. Please retry.")
       )}

  def handle_dispatch_result({:error, :handler, term}, socket) do
    require Logger
    Logger.error("command failed", error: inspect(term))
    {:noreply, LiveView.put_flash(socket, :error, gettext("Something went wrong."))}
  end
end
```

- [ ] **Step 4: Auto-import via `lib/web.ex`**

Locate the `live_view` and `live_component` macro definitions in `lib/web.ex` and add `import Web.BusUI` to their `quote` blocks (next to existing imports).

- [ ] **Step 5: Remove local defps from `PhotoCommentsComponent`**

In `lib/web/live/comments/photo_comments_component.ex`: delete the six local `defp handle_dispatch_result/2` clauses and the `require Logger` if no longer needed. Calls inside the file already match the imported function signature.

- [ ] **Step 6: Run gettext extract**

```bash
mix gettext.extract --merge
```

The strings move from the component to `Web.BusUI` — same msgid, just relocated. Verify Spanish translations are preserved (`priv/gettext/es-UY/LC_MESSAGES/default.po` should now reference `lib/web/bus_ui.ex`).

- [ ] **Step 7: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

Existing tests for `PhotoCommentsComponent` should still pass — the helper is now imported, not defined locally.

- [ ] **Step 8: Commit**

```bash
mix format
git add -A
git commit -m "Promote handle_dispatch_result to shared Web.BusUI helper"
```

---

### Task P0.5: Create `Ancestry.Bus.Step` DSL module

**Files:**
- Create: `lib/ancestry/bus/step.ex`
- Test: `test/ancestry/bus/step_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/ancestry/bus/step_test.exs
defmodule Ancestry.Bus.StepTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Audit.Log
  alias Ancestry.Bus.{Envelope, Step}
  alias Ecto.Multi

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

  defp envelope do
    {:ok, account} =
      %Ancestry.Identity.Account{
        email: "step-test@example.com",
        role: :admin,
        hashed_password: Bcrypt.hash_pwd_salt("x")
      }
      |> Ancestry.Repo.insert()

    Envelope.wrap(
      %Ancestry.Identity.Scope{account: account, organization: nil},
      FakeCommand.new!(%{label: "hello"})
    )
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

  test "enqueue/3 schedules an Oban job atomically with the transaction" do
    use Oban.Testing, repo: Ancestry.Repo

    env = envelope()

    multi =
      env
      |> Step.new()
      |> Step.enqueue(:job, fn _ ->
        Ancestry.Workers.TransformAndStorePhoto.new(%{photo_id: 1})
      end)

    {:ok, %{job: job}} = Ancestry.Repo.transaction(multi)
    assert %Oban.Job{} = job
    assert_enqueued(worker: Ancestry.Workers.TransformAndStorePhoto, args: %{"photo_id" => 1})
  end
end
```

> Note: the inline `fn` in the `effects/2` test is in **test code**, not a handler — handler rule does not apply. Acceptable.

- [ ] **Step 2: Run, confirm failure**

```bash
mix test test/ancestry/bus/step_test.exs
```

- [ ] **Step 3: Implement `Ancestry.Bus.Step`**

```elixir
# lib/ancestry/bus/step.ex
defmodule Ancestry.Bus.Step do
  @moduledoc """
  DSL for assembling handler transactions. Centralizes the reserved
  `:envelope`, `:audit`, and `:effects` steps; thin pass-throughs for
  the rest of `Ecto.Multi` and Oban.
  """

  alias Ancestry.Audit.Log
  alias Ecto.Multi

  @doc "Start a new transaction Multi seeded with the envelope."
  def new(envelope) do
    Multi.new() |> Multi.put(:envelope, envelope)
  end

  defdelegate put(multi, name, value), to: Multi
  defdelegate insert(multi, name, changeset_or_fun), to: Multi
  defdelegate insert(multi, name, changeset_or_fun, opts), to: Multi
  defdelegate update(multi, name, changeset_or_fun), to: Multi
  defdelegate delete(multi, name, struct_or_fun), to: Multi
  defdelegate run(multi, name, fun), to: Multi
  defdelegate delete_all(multi, name, queryable), to: Multi

  @doc "Atomically enqueue an Oban job alongside the rest of the transaction."
  defdelegate enqueue(multi, name, fun), to: Oban, as: :insert

  @doc "Append the audit step (writes one row to audit_log on commit)."
  def audit(multi), do: Multi.insert(multi, :audit, &create_audit_log/1)

  @doc "Append an effects step that returns the post-commit effect list."
  def effects(multi, fun), do: Multi.run(multi, :effects, fun)

  @doc "Append a no-op effects step. Convenience for handlers with nothing to fire."
  def no_effects(multi), do: effects(multi, &empty_effects/2)

  defp create_audit_log(%{envelope: envelope}), do: Log.changeset_from(envelope)
  defp empty_effects(_repo, _changes), do: {:ok, []}
end
```

- [ ] **Step 4: Run, confirm pass**

```bash
mix test test/ancestry/bus/step_test.exs
```

- [ ] **Step 5: Commit**

```bash
mix format lib/ancestry/bus/step.ex test/ancestry/bus/step_test.exs
git add lib/ancestry/bus/step.ex test/ancestry/bus/step_test.exs
git commit -m "Add Ancestry.Bus.Step DSL"
```

---

### Task P0.6: Migrate `Bus` dispatcher + `Handler` behaviour + comment handlers to `handle/1`

This is the biggest task in Phase 0 — atomic shift from `build_multi/1` to `handle/1`. All three existing comment handlers, the dispatcher, and the behaviour change in lockstep.

**Files:**
- Modify: `lib/ancestry/bus/handler.ex` (callback)
- Modify: `lib/ancestry/bus.ex` (dispatcher)
- Rewrite: `lib/ancestry/handlers/add_comment_to_photo_handler.ex`
- Rewrite: `lib/ancestry/handlers/update_photo_comment_handler.ex`
- Rewrite: `lib/ancestry/handlers/remove_comment_from_photo_handler.ex`
- Modify: `test/ancestry/bus_test.exs` (update test handlers + step name assertions)

- [ ] **Step 1: Update `Ancestry.Bus.Handler` behaviour**

```elixir
# lib/ancestry/bus/handler.ex
defmodule Ancestry.Bus.Handler do
  @moduledoc """
  Behaviour for command handlers. A handler exposes `handle/1` which
  runs the transaction and returns the result map (on success) or an
  Ecto.Multi error tuple (on failure).
  """

  @callback handle(Ancestry.Bus.Envelope.t()) ::
              {:ok, map()}
              | {:error, atom() | term(), term(), map()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Handler
    end
  end
end
```

- [ ] **Step 2: Update `Ancestry.Bus` dispatcher**

```elixir
# lib/ancestry/bus.ex (refactored run/2 + run_effect/1)
defp run(env, module) do
  case module.handled_by().handle(env) do
    {:ok, changes} ->
      Enum.each(changes[:effects] || [], &run_effect/1)
      {:ok, Map.fetch!(changes, module.primary_step())}

    {:error, _step, %Ecto.Changeset{} = cs, _changes} -> {:error, :validation, cs}
    {:error, _step, :not_found, _} -> {:error, :not_found}
    {:error, _step, {:not_found, _}, _} -> {:error, :not_found}
    {:error, _step, :unauthorized, _} -> {:error, :unauthorized}
    {:error, _step, {:conflict, t}, _} -> {:error, :conflict, t}
    {:error, _step, other, _} -> {:error, :handler, other}
  end
end

defp run_effect({:broadcast, topic, msg}),
  do: Phoenix.PubSub.broadcast(Ancestry.PubSub, topic, msg)
```

> Drop the `Multi.insert(:__audit__, ...)` line and the `:__effects__` reference. Remove `alias Ancestry.Audit` and `alias Ecto.Multi` if no longer used.

- [ ] **Step 3: Rewrite `AddCommentToPhotoHandler`**

```elixir
# lib/ancestry/handlers/add_comment_to_photo_handler.ex
defmodule Ancestry.Handlers.AddCommentToPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.AddCommentToPhoto`: insert the comment,
  preload its account, audit, broadcast its creation.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

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
```

Update the corresponding command's `primary_step/0` to return `:comment` (was `:preloaded`).

- [ ] **Step 4: Rewrite `UpdatePhotoCommentHandler`**

```elixir
# lib/ancestry/handlers/update_photo_comment_handler.ex
defmodule Ancestry.Handlers.UpdatePhotoCommentHandler do
  @moduledoc """
  Handles `Ancestry.Commands.UpdatePhotoComment`: authorize + update +
  preload + broadcast.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:authorized_comment, &authorize_comment_edit/2)
    |> Step.update(:updated_comment, &update_authorized_comment/1)
    |> Step.run(:comment, &preload_comment_account/2)
    |> Step.audit()
    |> Step.effects(&broadcast_update/2)
  end

  defp authorize_comment_edit(repo, %{envelope: envelope}) do
    %{command: command, scope: scope} = envelope

    case repo.get(PhotoComment, command.photo_comment_id) do
      nil ->
        {:error, :not_found}

      comment ->
        if comment.account_id == scope.account.id or scope.account.role == :admin do
          {:ok, comment}
        else
          {:error, :unauthorized}
        end
    end
  end

  defp update_authorized_comment(%{envelope: envelope, authorized_comment: comment}) do
    PhotoComment.changeset(comment, %{text: envelope.command.text})
  end

  defp preload_comment_account(repo, %{updated_comment: comment}) do
    {:ok, repo.preload(comment, :account)}
  end

  defp broadcast_update(_repo, %{comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_updated, comment}}]}
  end
end
```

Update the command's `primary_step/0` to `:comment`.

- [ ] **Step 5: Rewrite `RemoveCommentFromPhotoHandler`**

```elixir
# lib/ancestry/handlers/remove_comment_from_photo_handler.ex
defmodule Ancestry.Handlers.RemoveCommentFromPhotoHandler do
  @moduledoc """
  Handles `Ancestry.Commands.RemoveCommentFromPhoto`: authorize + load
  with account preloaded + delete + broadcast.
  """

  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Repo

  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:authorized_comment, &authorize_comment_deletion/2)
    |> Step.run(:comment, &remove_authorized_comment/2)
    |> Step.audit()
    |> Step.effects(&broadcast_deletion/2)
  end

  defp authorize_comment_deletion(repo, %{envelope: envelope}) do
    %{command: command, scope: scope} = envelope

    case repo.get(PhotoComment, command.photo_comment_id) do
      nil ->
        {:error, :not_found}

      comment ->
        comment = repo.preload(comment, :account)

        if comment.account_id == scope.account.id or scope.account.role == :admin do
          {:ok, comment}
        else
          {:error, :unauthorized}
        end
    end
  end

  defp remove_authorized_comment(repo, %{authorized_comment: comment}) do
    repo.delete(comment)
  end

  defp broadcast_deletion(_repo, %{authorized_comment: comment}) do
    {:ok, [{:broadcast, "photo_comments:#{comment.photo_id}", {:comment_deleted, comment}}]}
  end
end
```

Update the command's `primary_step/0` to `:comment`.

- [ ] **Step 6: Update `bus_test.exs` test handlers**

Replace all references to `build_multi/1` with `handle/1`, and `:__effects__` with `:effects`. Test helper handlers (e.g. `NoopHandler`, `NotFoundHandler`) need to be rewritten:

```elixir
# Example: NoopHandler refactor
defmodule NoopHandler do
  use Ancestry.Bus.Handler
  alias Ancestry.Bus.Step
  alias Ancestry.Repo

  @impl true
  def handle(envelope) do
    envelope
    |> Step.new()
    |> Step.put(:result, %{label: envelope.command.label, ok: true})
    |> Step.no_effects()
    |> Repo.transaction()
  end
end
```

Apply analogous refactors to `NotFoundHandler`, `ChangesetHandler`, `UnauthorizedStepHandler`, `HandlerErrorHandler`, `BroadcastingHandler`. Replace inline lambdas with named test-helper functions where they exist; for the simple test cases above, `Step.put/3` works for inserting fixed values.

> The `audit_log` row check in the existing tests still works — `Step.audit()` is called inside `Step.no_effects()` chain... wait, audit is separate. Add `Step.audit()` to test handlers that previously relied on dispatcher-prepended audit. Or update the test assertions to expect no audit row for the test handlers (since they don't call `Step.audit()`).
>
> For the existing test "`dispatch/2 returns the primary step result and writes an audit row`", the test handler must call `Step.audit()` to write the row. Add it to `NoopHandler`'s pipeline.

- [ ] **Step 7: Update integration tests for the three comment handlers**

Each existing handler test (e.g. `add_comment_to_photo_handler_test.exs`) asserts on the result map shape. Update key names: `:photo_comment` → `:inserted_comment`, `:preloaded` → `:comment`. Update `primary_step/0` assertion in command unit tests.

- [ ] **Step 8: Update user-flow tests**

In `test/user_flows/photo_comments_*.exs`, the `command_module` strings should match the renamed modules (already done in P0.2/P0.3). The `payload` keys match command struct fields (unchanged).

- [ ] **Step 9: Run full test suite**

```bash
mix compile --warnings-as-errors
mix test
```

Fix any remaining failures. All ~997 tests should pass.

- [ ] **Step 10: Commit**

```bash
mix format
git add -A
git commit -m "Refactor Bus + handlers to handle/1 + Step DSL"
```

---

## Phase 1 — Galleries

---

### Task P1.1: `Ancestry.Commands.AddGalleryToFamily`

**Files:**
- Create: `lib/ancestry/commands/add_gallery_to_family.ex`
- Test: `test/ancestry/commands/add_gallery_to_family_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Ancestry.Commands.AddGalleryToFamilyTest do
  use ExUnit.Case, async: true
  alias Ancestry.Commands.AddGalleryToFamily

  test "new/1 returns {:ok, command} for valid attrs" do
    assert {:ok, cmd} = AddGalleryToFamily.new(%{family_id: 1, name: "Trip"})
    assert %AddGalleryToFamily{family_id: 1, name: "Trip"} = cmd
  end

  test "new/1 rejects missing required fields" do
    assert {:error, %Ecto.Changeset{} = cs} = AddGalleryToFamily.new(%{})
    refute cs.valid?
    assert {"can't be blank", _} = cs.errors[:family_id]
    assert {"can't be blank", _} = cs.errors[:name]
  end

  test "new/1 enforces name length" do
    long = String.duplicate("a", 256)
    assert {:error, cs} = AddGalleryToFamily.new(%{family_id: 1, name: long})
    refute cs.valid?
    assert {"should be at most %{count} character(s)", _} = cs.errors[:name]
  end

  test "primary_step/0 == :gallery" do
    assert AddGalleryToFamily.primary_step() == :gallery
  end

  test "permission/0 == {:create, Gallery}" do
    assert AddGalleryToFamily.permission() == {:create, Ancestry.Galleries.Gallery}
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```bash
mix test test/ancestry/commands/add_gallery_to_family_test.exs
```

- [ ] **Step 3: Implement**

```elixir
defmodule Ancestry.Commands.AddGalleryToFamily do
  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Gallery

  @enforce_keys [:family_id, :name]
  defstruct [:family_id, :name]

  @types %{family_id: :integer, name: :string}
  @required Map.keys(@types)

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, @required)
      |> Ecto.Changeset.validate_required(@required)
      |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)

    if cs.valid?,
      do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, attrs)

  @impl true
  def handled_by, do: Ancestry.Handlers.AddGalleryToFamilyHandler

  @impl true
  def primary_step, do: :gallery

  @impl true
  def permission, do: {:create, Gallery}
end
```

- [ ] **Step 4: Run, confirm pass**

```bash
mix test test/ancestry/commands/add_gallery_to_family_test.exs
```

- [ ] **Step 5: Commit**

```bash
mix format lib/ancestry/commands/add_gallery_to_family.ex test/ancestry/commands/add_gallery_to_family_test.exs
git add -A
git commit -m "Add Ancestry.Commands.AddGalleryToFamily"
```

---

### Task P1.2: `Ancestry.Handlers.AddGalleryToFamilyHandler`

**Files:**
- Create: `lib/ancestry/handlers/add_gallery_to_family_handler.ex`
- Test: `test/ancestry/handlers/add_gallery_to_family_handler_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
defmodule Ancestry.Handlers.AddGalleryToFamilyHandlerTest do
  use Ancestry.DataCase, async: false

  import Ancestry.Factory

  alias Ancestry.Bus
  alias Ancestry.Commands.AddGalleryToFamily
  alias Ancestry.Galleries.Gallery

  setup do
    organization = insert(:organization)
    family = insert(:family, organization: organization)
    account = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    {:ok, scope: scope, family: family}
  end

  test "Bus.dispatch creates a gallery and writes an audit row", %{scope: scope, family: family} do
    {:ok, cmd} = AddGalleryToFamily.new(%{family_id: family.id, name: "Trip"})

    assert {:ok, %Gallery{name: "Trip"} = gallery} = Bus.dispatch(scope, cmd)
    assert gallery.family_id == family.id

    assert [row] = Ancestry.Repo.all(Ancestry.Audit.Log)
    assert row.command_module == "Ancestry.Commands.AddGalleryToFamily"
    assert row.payload["name"] == "Trip"
    assert row.payload["family_id"] == family.id
  end

  test "Bus.dispatch returns :validation for invalid family_id", %{scope: scope} do
    cmd = AddGalleryToFamily.new!(%{family_id: -1, name: "Trip"})

    assert {:error, :validation, %Ecto.Changeset{}} = Bus.dispatch(scope, cmd)
    assert Ancestry.Repo.all(Ancestry.Audit.Log) == []
  end
end
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement**

```elixir
defmodule Ancestry.Handlers.AddGalleryToFamilyHandler do
  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Repo

  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.insert(:gallery, &add_gallery_to_family/1)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp add_gallery_to_family(%{envelope: envelope}) do
    %Gallery{}
    |> Gallery.changeset(Map.from_struct(envelope.command))
  end
end
```

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
mix format lib/ancestry/handlers/add_gallery_to_family_handler.ex test/ancestry/handlers/add_gallery_to_family_handler_test.exs
git add -A
git commit -m "Add AddGalleryToFamily handler"
```

---

### Task P1.3: `Ancestry.Commands.RemoveGalleryFromFamily`

**Files:**
- Create: `lib/ancestry/commands/remove_gallery_from_family.ex`
- Test: `test/ancestry/commands/remove_gallery_from_family_test.exs`

Mirror Task P1.1 with fields `[:gallery_id]`, validations `gallery_id` integer required, `permission/0` `{:delete, Gallery}`, `primary_step/0` `:gallery`.

- [ ] **Step 1–5:** TDD per Task P1.1 pattern.

```bash
git commit -m "Add Ancestry.Commands.RemoveGalleryFromFamily"
```

---

### Task P1.4: `Ancestry.Handlers.RemoveGalleryFromFamilyHandler`

**Files:**
- Create: `lib/ancestry/handlers/remove_gallery_from_family_handler.ex`
- Test: `test/ancestry/handlers/remove_gallery_from_family_handler_test.exs`

- [ ] **Step 1: Write failing test**

Cover: success → audit row written + cascade verified (photos / photo_people / photo_comments removed); `:not_found` for missing id.

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement**

```elixir
defmodule Ancestry.Handlers.RemoveGalleryFromFamilyHandler do
  use Ancestry.Bus.Handler

  alias Ancestry.Bus.Step
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Repo

  def handle(envelope) do
    envelope |> to_transaction() |> Repo.transaction()
  end

  defp to_transaction(envelope) do
    Step.new(envelope)
    |> Step.run(:gallery, &remove_gallery/2)
    |> Step.audit()
    |> Step.no_effects()
  end

  defp remove_gallery(repo, %{envelope: envelope}) do
    case repo.get(Gallery, envelope.command.gallery_id) do
      nil -> {:error, :not_found}
      gallery -> repo.delete(gallery)
    end
  end
end
```

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add RemoveGalleryFromFamily handler"
```

---

### Task P1.5: Rewire `family_live/show.ex`

**Files:**
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Locate `save_gallery` handler**

Currently calls `Galleries.create_gallery(params)`. Replace:

```elixir
def handle_event("save_gallery", %{"gallery" => params}, socket) do
  attrs = Map.put(params, "family_id", socket.assigns.family.id)

  case Ancestry.Commands.AddGalleryToFamily.new(attrs) do
    {:ok, command} ->
      socket.assigns.current_scope
      |> Ancestry.Bus.dispatch(command)
      |> handle_dispatch_result(socket)

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset, as: :gallery))}
  end
end
```

- [ ] **Step 2: Locate `delete_gallery` handler**

Replace `Galleries.delete_gallery(gallery)` with:

```elixir
def handle_event("delete_gallery", %{"id" => id}, socket) do
  command = Ancestry.Commands.RemoveGalleryFromFamily.new!(%{gallery_id: String.to_integer(id)})

  socket.assigns.current_scope
  |> Ancestry.Bus.dispatch(command)
  |> handle_dispatch_result(socket)
end
```

> If existing UI logic post-success removed the gallery from a stream / redirected, that logic needs to compose with the dispatcher result. Check the original code carefully. Pattern match on `Bus.dispatch/2` directly when extra UI work is needed:
>
> ```elixir
> case Bus.dispatch(scope, command) do
>   {:ok, _} = result ->
>     {:noreply, socket} = handle_dispatch_result(result, socket)
>     {:noreply, push_navigate(socket, to: ~p"/org/#{org_id}/families/#{family.id}")}
>   error ->
>     handle_dispatch_result(error, socket)
> end
> ```

- [ ] **Step 3: Run existing tests**

```bash
mix test test/user_flows/create_family_test.exs test/web/live/family_live/
```

Fix any breakage.

- [ ] **Step 4: Commit**

```bash
mix format lib/web/live/family_live/show.ex
git add lib/web/live/family_live/show.ex
git commit -m "Wire gallery create/delete through Ancestry.Bus"
```

---

### Task P1.6: User-flow test `gallery_create_test.exs`

**Files:**
- Create: `test/user_flows/gallery_create_test.exs`

- [ ] **Step 1: Write the test**

```elixir
defmodule Web.UserFlows.GalleryCreateTest do
  @moduledoc """
  Verifies that creating a gallery via the family-show LiveView dispatches
  `AddGalleryToFamily` through the Bus and writes an audit row.
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    %{org: org, family: family}
  end

  test "creates a gallery via the bus and writes an audit row",
       %{conn: conn, org: org, family: family} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")

    # Open new-gallery form (selector depends on the current template — verify with
    # mix test on the existing family flow; copy the open-form interaction from there)
    view |> element("#open-new-gallery-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: "Summer Trip"})
    |> render_submit()

    assert [gallery] = Repo.all(Gallery)
    assert gallery.name == "Summer Trip"

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddGalleryToFamily"
    assert row.payload["name"] == "Summer Trip"
  end
end
```

- [ ] **Step 2: Run, confirm pass**

```bash
mix test test/user_flows/gallery_create_test.exs
```

If selectors don't match the current template, copy the working interaction from an existing family/gallery test (e.g. `test/user_flows/create_family_test.exs`).

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/gallery_create_test.exs
git commit -m "E2E test: gallery creation via Bus"
```

---

### Task P1.7: User-flow test `gallery_delete_test.exs`

**Files:**
- Create: `test/user_flows/gallery_delete_test.exs`

Cover: gallery delete → audit row + cascade verification (photos in the gallery removed).

- [ ] **Step 1: Write the test** (mirror P1.6 shape; assert cascade by inserting a photo + photo_person + photo_comment, deleting the gallery, then asserting all three rows are gone via `Repo.all/1` queries).

- [ ] **Step 2: Run, confirm pass**

- [ ] **Step 3: Commit**

```bash
git commit -m "E2E test: gallery deletion via Bus + cascade"
```

---

### Task P1.8: Strip `Galleries.create_gallery/1` and `Galleries.delete_gallery/1`

**Files:**
- Modify: `lib/ancestry/galleries.ex`

- [ ] **Step 1: Inspect current state + callsites**

```bash
grep -rn "Galleries.create_gallery\|Galleries.delete_gallery" lib/ test/
```

Expected: zero callsites in `lib/`. Test fixtures may use `insert(:gallery)` factory — that's fine.

If any test still calls `Galleries.create_gallery/1` directly (e.g. setup helpers), migrate to `insert(:gallery, ...)`.

- [ ] **Step 2: Delete the functions**

In `lib/ancestry/galleries.ex`, remove `create_gallery/1` and `delete_gallery/1`.

- [ ] **Step 3: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

- [ ] **Step 4: Commit**

```bash
mix format lib/ancestry/galleries.ex
git add -A
git commit -m "Strip create_gallery and delete_gallery from Ancestry.Galleries"
```

---

## Phase 2 — Photos

---

### Task P2.1: `Ancestry.Commands.AddPhotoToGallery`

**Files:**
- Create: `lib/ancestry/commands/add_photo_to_gallery.ex`
- Test: `test/ancestry/commands/add_photo_to_gallery_test.exs`

- [ ] **Step 1: Test**

Required fields: `gallery_id, original_path, original_filename, content_type, file_hash`. Permission `{:create, Photo}`. Primary step `:photo`.

- [ ] **Step 2–5:** TDD per Task P1.1.

```bash
git commit -m "Add Ancestry.Commands.AddPhotoToGallery"
```

---

### Task P2.2: `Ancestry.Handlers.AddPhotoToGalleryHandler`

**Files:**
- Create: `lib/ancestry/handlers/add_photo_to_gallery_handler.ex`
- Test: `test/ancestry/handlers/add_photo_to_gallery_handler_test.exs`

- [ ] **Step 1: Write failing test**

Cover:
- Success → photo inserted, gallery preloaded, Oban job enqueued (`assert_enqueued`), audit row written, `:effects` is empty list.
- Validation failure (missing field) → `:validation` error, no DB writes.

```elixir
test "Bus.dispatch creates photo + enqueues TransformAndStorePhoto + audits", %{scope: scope, gallery: gallery} do
  use Oban.Testing, repo: Ancestry.Repo

  attrs = %{
    gallery_id: gallery.id,
    original_path: "/tmp/test.jpg",
    original_filename: "test.jpg",
    content_type: "image/jpeg",
    file_hash: "abc123"
  }

  {:ok, cmd} = AddPhotoToGallery.new(attrs)
  assert {:ok, %Photo{} = photo} = Bus.dispatch(scope, cmd)

  assert photo.gallery.id == gallery.id
  assert_enqueued(worker: TransformAndStorePhoto, args: %{"photo_id" => photo.id})

  assert [row] = Repo.all(Log)
  assert row.command_module == "Ancestry.Commands.AddPhotoToGallery"
  assert row.payload["file_hash"] == "abc123"
end
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement** (per spec §`AddPhotoToGalleryHandler`)

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add AddPhotoToGallery handler with Oban enqueue"
```

---

### Task P2.3: `Ancestry.Commands.RemovePhotoFromGallery`

Mirror P1.3.

- [ ] **Step 1–5:** TDD with field `[:photo_id]`, permission `{:delete, Photo}`, primary step `:photo`.

```bash
git commit -m "Add Ancestry.Commands.RemovePhotoFromGallery"
```

---

### Task P2.4: Add `:waffle_delete` effect kind to dispatcher

**Files:**
- Modify: `lib/ancestry/bus.ex`
- Modify: `test/ancestry/bus_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
test "fires :waffle_delete effects after commit (no-op when image is nil)" do
  # ... build a fake Photo struct (or use insert(:photo)) with image: nil
  # dispatch a handler that emits {:waffle_delete, photo}
  # assert the dispatch returns {:ok, _} and no error is raised
end
```

> The Waffle uploader's `delete/1` is a side effect against the test storage adapter. For unit-testing the dispatcher's effect handler, a mock photo struct with `image: nil` is sufficient (the dispatcher's clause for `image: nil` returns `:ok`).

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement**

In `lib/ancestry/bus.ex`, add to the `run_effect/1` clauses:

```elixir
defp run_effect({:waffle_delete, %Ancestry.Galleries.Photo{image: img} = photo})
     when not is_nil(img),
     do: Ancestry.Uploaders.Photo.delete({img, photo})

defp run_effect({:waffle_delete, _}), do: :ok
```

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add :waffle_delete effect kind to Ancestry.Bus"
```

---

### Task P2.5: `Ancestry.Handlers.RemovePhotoFromGalleryHandler`

**Files:**
- Create: `lib/ancestry/handlers/remove_photo_from_gallery_handler.ex`
- Test: `test/ancestry/handlers/remove_photo_from_gallery_handler_test.exs`

- [ ] **Step 1: Test** — cover success → audit row + `{:waffle_delete, photo}` in effects (assert via subscribing/inspecting changes); `:not_found` for missing id.

- [ ] **Step 2: Run-fail**

- [ ] **Step 3: Implement** (per spec §`RemovePhotoFromGalleryHandler`)

- [ ] **Step 4: Run-pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add RemovePhotoFromGallery handler with storage cleanup"
```

---

### Task P2.6: Rewire `gallery_live/show.ex` photo upload (pre-flight)

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` (`process_uploads/1`)

- [ ] **Step 1: Replace the upload loop**

```elixir
results =
  consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
    contents = File.read!(tmp_path)
    file_hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

    cond do
      Galleries.photo_exists_in_gallery?(gallery.id, file_hash) ->
        {:ok, {:duplicate, entry.client_name}}

      true ->
        original_path =
          Ancestry.Storage.store_original_bytes(
            contents,
            Path.join(["uploads", "originals", Ecto.UUID.generate(),
                       "photo#{ext_from_content_type(entry.client_type)}"])
          )

        attrs = %{
          gallery_id: gallery.id,
          original_path: original_path,
          original_filename: entry.client_name,
          content_type: entry.client_type,
          file_hash: file_hash
        }

        case Ancestry.Bus.dispatch(
               socket.assigns.current_scope,
               Ancestry.Commands.AddPhotoToGallery.new!(attrs)
             ) do
          {:ok, photo} -> {:ok, {:ok, photo}}
          {:error, _} -> {:ok, {:error, entry.client_name}}
        end
    end
  end)
```

- [ ] **Step 2: Run existing photo upload tests**

```bash
mix test test/user_flows/photo_*_test.exs test/web/live/gallery_live/
```

Fix any breakage.

- [ ] **Step 3: Commit**

```bash
mix format lib/web/live/gallery_live/show.ex
git add lib/web/live/gallery_live/show.ex
git commit -m "Wire photo upload through Ancestry.Bus"
```

---

### Task P2.7: Rewire `gallery_live/show.ex` photo delete

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` (`confirm_delete_photos`)

- [ ] **Step 1: Replace the delete loop**

```elixir
def handle_event("confirm_delete_photos", _, socket) do
  scope = socket.assigns.current_scope

  socket =
    Enum.reduce(MapSet.to_list(socket.assigns.selected_ids), socket, fn id, acc ->
      command = Ancestry.Commands.RemovePhotoFromGallery.new!(%{photo_id: id})

      case Ancestry.Bus.dispatch(scope, command) do
        {:ok, photo} -> stream_delete(acc, :photos, photo)
        {:error, _} -> acc
      end
    end)

  # ... rest unchanged ...
end
```

- [ ] **Step 2–4:** verify + commit

```bash
git commit -m "Wire bulk photo delete through Ancestry.Bus"
```

---

### Task P2.8: User-flow test `photo_upload_test.exs`

**Files:**
- Create: `test/user_flows/photo_upload_test.exs`

Cover: upload single photo → audit row + Oban job enqueued; duplicate hash → no audit row, error in upload results; invalid content type pre-flight failure.

- [ ] **Step 1–3:** mirror P1.6 shape using `file_input/3` from existing photo upload tests.

```bash
git commit -m "E2E test: photo upload via Bus"
```

---

### Task P2.9: User-flow test `photo_delete_test.exs`

**Files:**
- Create: `test/user_flows/photo_delete_test.exs`

Cover: select photo → confirm delete → audit row + photo removed from DB + Waffle delete effect fired (assert the local file is gone).

- [ ] **Step 1–3:** mirror P1.7 shape.

```bash
git commit -m "E2E test: photo delete via Bus + storage cleanup"
```

---

### Task P2.10: Strip photo mutations from `Ancestry.Galleries`

**Files:**
- Modify: `lib/ancestry/galleries.ex`

- [ ] **Step 1: Inspect callsites**

```bash
grep -rn "Galleries.create_photo\|Galleries.delete_photo" lib/ test/
```

Expected: zero callsites in `lib/`. Worker uses `update_photo_processed/2` and `update_photo_failed/1` which stay.

- [ ] **Step 2: Remove `create_photo/1` and `delete_photo/1`**

- [ ] **Step 3: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

- [ ] **Step 4: Commit**

```bash
git commit -m "Strip create_photo and delete_photo from Ancestry.Galleries"
```

---

## Phase 3 — Tags

---

### Task P3.1: `Ancestry.Commands.TagPersonInPhoto`

**Files:**
- Create: `lib/ancestry/commands/tag_person_in_photo.ex`
- Test: `test/ancestry/commands/tag_person_in_photo_test.exs`

Fields `[:photo_id, :person_id, :x, :y]`. `x` and `y` floats or nil. Validation: if either is set, both set, both in `[0.0, 1.0]`. Permission `{:update, Photo}`. Primary step `:photo_person`.

- [ ] **Step 1: Test** — cover valid attrs (both with and without coords); reject mismatched coord state (one set, the other nil); reject out-of-range values.

```bash
git commit -m "Add Ancestry.Commands.TagPersonInPhoto"
```

---

### Task P3.2: `Ancestry.Handlers.TagPersonInPhotoHandler`

**Files:**
- Create: `lib/ancestry/handlers/tag_person_in_photo_handler.ex`
- Test: `test/ancestry/handlers/tag_person_in_photo_handler_test.exs`

- [ ] **Step 1: Test** — cover insert (new tag), update (existing tag, same person+photo, new coords); audit row written.

- [ ] **Step 2: Run-fail**

- [ ] **Step 3: Implement** (per spec §`TagPersonInPhotoHandler`)

- [ ] **Step 4: Run-pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add TagPersonInPhoto handler with upsert"
```

---

### Task P3.3: `Ancestry.Commands.UntagPersonFromPhoto`

Fields `[:photo_id, :person_id]`. Permission `{:update, Photo}`. Primary step `:tag` (atom `:ok`).

- [ ] **Step 1–5:** TDD per pattern.

```bash
git commit -m "Add Ancestry.Commands.UntagPersonFromPhoto"
```

---

### Task P3.4: `Ancestry.Handlers.UntagPersonFromPhotoHandler`

- [ ] **Step 1: Test** — cover happy path (existing tag deleted), no-op for non-existent tag (delete_all returns 0; still `{:ok, :ok}`), audit row written.

- [ ] **Step 2: Run-fail**

- [ ] **Step 3: Implement** (per spec)

- [ ] **Step 4: Run-pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "Add UntagPersonFromPhoto handler"
```

---

### Task P3.5: Rewire `photo_interactions.ex` tag/untag/link

**Files:**
- Modify: `lib/web/photo_interactions.ex`

- [ ] **Step 1: Replace `tag_person/4`**

```elixir
def tag_person(socket, person_id, x, y) do
  photo = socket.assigns.selected_photo

  command = Ancestry.Commands.TagPersonInPhoto.new!(%{
    photo_id: photo.id,
    person_id: String.to_integer(person_id),
    x: x, y: y
  })

  case Ancestry.Bus.dispatch(socket.assigns.current_scope, command) do
    {:ok, _} ->
      socket
      |> assign(:photo_people, Galleries.list_photo_people(photo.id))
      |> push_photo_people()

    {:error, _} ->
      socket
  end
end
```

- [ ] **Step 2: Replace `untag_person/3`**

```elixir
def untag_person(socket, photo_id, person_id) do
  command = Ancestry.Commands.UntagPersonFromPhoto.new!(%{
    photo_id: String.to_integer(photo_id),
    person_id: String.to_integer(person_id)
  })

  case Ancestry.Bus.dispatch(socket.assigns.current_scope, command) do
    {:ok, _} ->
      socket
      |> assign(:photo_people, Galleries.list_photo_people(socket.assigns.selected_photo.id))
      |> push_photo_people()

    {:error, _} ->
      socket
  end
end
```

- [ ] **Step 3: Replace `link_existing_person/2`**

```elixir
def link_existing_person(socket, person_id) do
  photo = socket.assigns.selected_photo

  command = Ancestry.Commands.TagPersonInPhoto.new!(%{
    photo_id: photo.id,
    person_id: String.to_integer(person_id),
    x: nil, y: nil
  })

  Ancestry.Bus.dispatch(socket.assigns.current_scope, command)
  # ... existing follow-up unchanged ...
end
```

- [ ] **Step 4: Verify + commit**

```bash
mix test test/web/photo_interactions_test.exs test/web/live/gallery_live/
git commit -m "Wire tag/untag/link UI events through Ancestry.Bus"
```

---

### Task P3.6: Rewire `gallery_live/show.ex` quick-create tag fan-out

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` (`handle_info({:person_created, ...})`)

Replace `Galleries.tag_person_in_photo(photo_id, person.id, x, y)` with `Bus.dispatch(scope, TagPersonInPhoto.new!(...))`.

- [ ] **Step 1–4:** verify + commit

```bash
git commit -m "Wire gallery quick-create tag through Ancestry.Bus"
```

---

### Task P3.7: Rewire `person_live/show.ex` quick-create tag fan-out

**Files:**
- Modify: `lib/web/live/person_live/show.ex`

Same pattern as P3.6.

- [ ] **Step 1–4:** verify + commit

```bash
git commit -m "Wire person quick-create tag through Ancestry.Bus"
```

---

### Task P3.8: User-flow test `photo_tag_test.exs`

**Files:**
- Create: `test/user_flows/photo_tag_test.exs`

Cover: tag a person in a photo (with coords) → audit row; untag → audit row; existing tag → upsert updates coords (one row in DB); link existing person without coords.

- [ ] **Step 1–3:** mirror P1.6 shape.

```bash
git commit -m "E2E test: photo tag/untag via Bus"
```

---

### Task P3.9: Strip tag mutations from `Ancestry.Galleries`

**Files:**
- Modify: `lib/ancestry/galleries.ex`

- [ ] **Step 1: Inspect callsites**

```bash
grep -rn "Galleries.tag_person_in_photo\|Galleries.untag_person_from_photo" lib/ test/
```

- [ ] **Step 2: Remove `tag_person_in_photo/4` and `untag_person_from_photo/2`**

- [ ] **Step 3: Verify**

```bash
mix compile --warnings-as-errors
mix test
```

- [ ] **Step 4: Commit**

```bash
git commit -m "Strip tag mutations from Ancestry.Galleries"
```

---

## Phase 4 — Final verification

---

### Task P4.1: `mix precommit`

- [ ] **Step 1: Run precommit**

```bash
mix precommit
```

Expected: clean compile (no warnings), all tests green, `mix format` clean, no unused deps. Fix any failures and commit fixes individually before proceeding.

- [ ] **Step 2: Verify `Ancestry.Galleries` is queries-only**

```bash
grep -n "def " lib/ancestry/galleries.ex
```

Expected public functions: `list_galleries/1`, `get_gallery!/1`, `change_gallery/2`, `list_photos/1`, `get_photo!/1`, `update_photo_processed/2`, `update_photo_failed/1`, `photo_exists_in_gallery?/2`, `list_photo_people/1`, `list_photos_for_person/1`. No `create_*`, `delete_*`, `tag_*`, `untag_*`.

- [ ] **Step 3: Verify branch shape**

```bash
git log --oneline 9076b89^..HEAD
```

Each commit small and named per the conventions established in the photo-comment migration.

---

### Task P4.2: Manual smoke + audit_log inspection

- [ ] **Step 1: Start dev server**

```bash
iex -S mix phx.server
```

- [ ] **Step 2: Exercise each flow**

- Log in as an admin/editor
- Create a gallery → confirm UI updates
- Upload a photo → confirm processing completes (`:photo_processed` PubSub fires; UI updates)
- Tag a person in the photo → confirm tag appears
- Untag the person → confirm tag disappears
- Delete the photo → confirm UI removes it AND the local file in `priv/static/uploads/photos/...` is gone
- Delete the gallery → confirm cascade (any remaining photos disappear from the UI)

- [ ] **Step 3: Inspect `audit_log` via Tidewave**

```sql
SELECT command_module, count(*)
FROM audit_log
WHERE inserted_at > NOW() - INTERVAL '15 minutes'
GROUP BY command_module
ORDER BY command_module;
```

Expected rows for at minimum: `Ancestry.Commands.AddGalleryToFamily`, `Ancestry.Commands.AddPhotoToGallery`, `Ancestry.Commands.TagPersonInPhoto`, `Ancestry.Commands.UntagPersonFromPhoto`, `Ancestry.Commands.RemovePhotoFromGallery`, `Ancestry.Commands.RemoveGalleryFromFamily`.

- [ ] **Step 4: Final commit (no-op or summary)**

If any cleanup or doc updates fall out of the smoke test, commit them now. Otherwise the branch is ready for review/merge.

```bash
git log --oneline commands ^main
```

---

## Open follow-ups (NOT in this plan)

- Auditing failures (validation/authz/exceptions) into a separate sink.
- Migrating other contexts (`Families`, `People`, `Identity`, `Memories`, `Relationships`, `Import`).
- Worker-event audit sink for `update_photo_processed/2` / `update_photo_failed/1`.
- S3 lifecycle / orphan cleanup.
- Real-time `:photo_created` / `:photo_deleted` / `:tag_added` broadcasts for cross-client UI sync.
- Entity external IDs and URL changes.

---

## Notes for the executing engineer

- This plan extends the photo-comment migration on the same `commands` branch. Read both specs and the prior plan first.
- `CLAUDE.md` — particularly the `Command/Handler Architecture (Bus)` and `Patterns to use in the project → Ecto` sections — is the source of truth.
- Use `Ancestry.Bus.Step` exclusively in handler bodies. Never call `Multi.*` or `Oban.*` directly from a handler.
- Story-driven naming is non-negotiable: step names are nouns, function names are action verbs, no `_changeset`/`_attrs`/`_params` suffixes, no inline anonymous functions.
- Insert+preload always splits into two steps: `:inserted_<thing>` then `:<thing>`. Same for update.
- After every code-touching task, `mix compile --warnings-as-errors` must pass before commit.
- Use Tidewave (`get_ecto_schemas`, `get_source_location`, `project_eval`, `execute_sql_query`, `get_logs`) before guessing about runtime state.
- Final phase runs `mix precommit`. Do not skip.
