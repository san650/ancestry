# Galleries Context — Command/Handler Migration

**Status:** Design — pending implementation plan
**Date:** 2026-05-08
**Branch:** `commands` (continuation of the photo-comment migration on the same branch)
**Predecessor:** `docs/plans/2026-05-07-command-handler-foundation.md` (photo comments migration)

## Goal

Migrate every state-mutating operation in the `Ancestry.Galleries` context to dispatch through `Ancestry.Bus`. Six new commands cover gallery create/delete, photo create/delete, and person-tag create/delete. The context drops to queries-only, mirroring the post-migration shape of `Ancestry.Comments`. Worker writes (`update_photo_processed/2`, `update_photo_failed/1`) stay direct.

This work also tightens the architecture established in the photo-comment migration:

- Introduces `Ancestry.Bus.Step` — a thin DSL over `Ecto.Multi` + Oban that standardizes the reserved `:envelope` / `:audit` / `:effects` steps and provides verb-named helpers.
- Replaces the `build_multi/1` callback with `handle/1` (handlers own the transaction).
- Renames magic step names: `:__audit__` → `:audit`, `:__effects__` → `:effects`.
- Renames the existing comment commands to follow the action-relationship naming convention: `CreatePhotoComment` → `AddCommentToPhoto`, `DeletePhotoComment` → `RemoveCommentFromPhoto`.
- Renames the photo Oban worker `ProcessPhotoJob` → `TransformAndStorePhoto` (describes what it actually does).

## Motivation

`Ancestry.Galleries` is the largest mutable context in the app and the natural next slice of the audit-log rollout. Photo upload, in particular, is the gnarliest path in the codebase (S3 pre-flight, Oban enqueue, real-time PubSub from a worker) and migrating it validates that the Bus pattern handles non-trivial flows.

The architectural refinements (`Step` DSL, `handle/1`, no magic step names) lower the cost of every future migration: each new handler reads as a story of named action verbs, with reserved framework concerns hidden behind `Step.audit()` / `Step.effects/1`.

## Scope

### In scope

1. Six new commands + handlers covering all human-driven mutations on `Galleries`:
   - `AddGalleryToFamily` / `RemoveGalleryFromFamily`
   - `AddPhotoToGallery` / `RemovePhotoFromGallery`
   - `TagPersonInPhoto` / `UntagPersonFromPhoto`
2. New module `Ancestry.Bus.Step` (DSL).
3. Refactor of `Ancestry.Bus` dispatcher: `handle/1` callback, drop `:__audit__` prepend (handler owns it via `Step.audit()`), rename `:__effects__` → `:effects`, add `:waffle_delete` effect kind.
4. Rename `CreatePhotoComment` → `AddCommentToPhoto`, `DeletePhotoComment` → `RemoveCommentFromPhoto`. Refactor all three existing comment handlers to the new shape.
5. Rename `Ancestry.Workers.ProcessPhotoJob` → `Ancestry.Workers.TransformAndStorePhoto`.
6. Promote `handle_dispatch_result/2` from `PhotoCommentsComponent` to a shared `Web.BusUI` helper, auto-imported into all LiveViews/components.
7. Rewire LiveView callsites in `family_live/show.ex`, `gallery_live/show.ex`, `person_live/show.ex`, `photo_interactions.ex`.
8. Strip the migrated mutation functions from `Ancestry.Galleries` (queries only post-migration).
9. New user-flow tests for each command (create, delete, error states).

### Out of scope

- Migrating worker writes (`update_photo_processed/2`, `update_photo_failed/1`) to the Bus. Workers have no human scope; `audit_log.account_id` is `NOT NULL`. Deferred to a separate worker-event sink if needed.
- Adding `external_id` columns to `Gallery`, `Photo`, etc.
- Replacing numeric ids in URLs.
- Migrating `Ancestry.Families`, `Ancestry.People`, `Ancestry.Identity`, etc.
- Auditing failures (validation/authz/exceptions) — failures continue to flow through `:telemetry` + `Logger`.
- Real-time cross-client broadcasts on photo create/delete or tag add/remove (current behavior preserves local-stream-only updates; not regressed, not improved).
- Cleanup of orphaned S3 objects on gallery cascade delete (current behavior — cascade deletes photos via FK, S3 originals are left; preserved per the locked S3 stance).

## Decisions (locked)

| Concern | Decision |
|---|---|
| Command naming | Action + entity + preposition + container for relational ops (`AddPhotoToGallery`, `RemovePhotoFromGallery`, `AddCommentToPhoto`, `RemoveCommentFromPhoto`, `AddGalleryToFamily`, `RemoveGalleryFromFamily`). Pure entity update: `Update{Entity}` (`UpdatePhotoComment`). Idiomatic verbs for natural cases (`TagPersonInPhoto`, `UntagPersonFromPhoto`). |
| Worker writes | Stay direct (option 4 from brainstorm). Workers do not dispatch through the Bus. |
| Photo upload S3 | Pre-flight in the LiveView (caller). On S3 failure, no dispatch. On DB failure after S3 success, S3 original is left orphaned (accepted; cleanup deferred). |
| Photo delete S3 | Post-commit `:waffle_delete` effect. The dispatcher fires `Ancestry.Uploaders.Photo.delete/1` after the DB transaction commits. |
| Gallery delete | Single `Multi.run` step that loads + deletes the gallery. FK cascades photos / photo_people / photo_comments. No per-photo Bus dispatch on cascade. S3 originals for cascaded photos are not cleaned up (preserves current behavior; accepted). |
| Tag authorization | `{:update, Photo}` for both tag and untag — piggybacks on existing Permit rules. No new Permit resource for `PhotoPerson`. |
| Handler public surface | `def handle(envelope)` only. Body is always `envelope \|> to_transaction() \|> Repo.transaction()`. |
| Multi DSL | All handlers use `Ancestry.Bus.Step` exclusively — never call `Multi.*` or `Oban.*` directly. Reserved step names: `:envelope`, `:audit`, `:effects`. |
| Insert+preload pattern | Always two steps. Bare mutation: `:inserted_<thing>` (or `:updated_<thing>`). Preload: `:<thing>` (the bare-noun step holds the final state used by `primary_step/0` and effects). |
| Multi steps | All step functions are named `defp` (no inline lambdas, even for one-liners). Story-driven step names — nouns describing resulting state; functions are action verbs. |
| Audit step | Handler-owned via `Step.audit()` (no longer dispatcher-prepended). |
| Effects step | Handler-owned via `Step.effects(&...)` or `Step.no_effects()`. Dispatcher reads `changes[:effects]` post-commit. |
| Effect kinds | `{:broadcast, topic, msg}` (existing) + `{:waffle_delete, %Photo{}}` (new). |
| Branch strategy | All commits land directly on the `commands` branch. No PRs. Phases are commit groups, not merge boundaries. |

## Module layout

```
lib/ancestry/bus/
  step.ex                                    NEW

lib/ancestry/commands/
  add_gallery_to_family.ex                   NEW
  remove_gallery_from_family.ex              NEW
  add_photo_to_gallery.ex                    NEW
  remove_photo_from_gallery.ex               NEW
  tag_person_in_photo.ex                     NEW
  untag_person_from_photo.ex                 NEW
  add_comment_to_photo.ex                    RENAME from create_photo_comment.ex
  remove_comment_from_photo.ex               RENAME from delete_photo_comment.ex
  update_photo_comment.ex                    REFACTOR (Step DSL, split update+preload)

lib/ancestry/handlers/
  add_gallery_to_family_handler.ex           NEW
  remove_gallery_from_family_handler.ex      NEW
  add_photo_to_gallery_handler.ex            NEW
  remove_photo_from_gallery_handler.ex       NEW
  tag_person_in_photo_handler.ex             NEW
  untag_person_from_photo_handler.ex         NEW
  add_comment_to_photo_handler.ex            RENAME + REFACTOR
  remove_comment_from_photo_handler.ex       RENAME + REFACTOR
  update_photo_comment_handler.ex            REFACTOR

lib/ancestry/galleries.ex                    REDUCED to queries only
lib/ancestry/bus.ex                          REFACTOR (handle/1, :audit/:effects, :waffle_delete)
lib/ancestry/bus/handler.ex                  REFACTOR (handle/1 callback)

lib/ancestry/workers/transform_and_store_photo.ex   RENAME from process_photo_job.ex

lib/web/
  bus_ui.ex                                  NEW (handle_dispatch_result/2)
  web.ex                                     UPDATE (auto-import BusUI)
  live/family_live/show.ex                   REWIRE (gallery create/delete)
  live/gallery_live/show.ex                  REWIRE (photo upload/delete, quick-create tag)
  live/person_live/show.ex                   REWIRE (quick-create tag)
  photo_interactions.ex                      REWIRE (tag/untag UI events, link_existing)
  live/comments/photo_comments_component.ex  REFACTOR (drop local handle_dispatch_result/2)
```

## `Ancestry.Bus.Step`

```elixir
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

`Ancestry.Bus.Effects` (created during the photo-comment migration) becomes redundant and is deleted.

## Handler shape (locked across all 9 handlers)

Common public surface:

```elixir
def handle(envelope) do
  envelope |> to_transaction() |> Repo.transaction()
end
```

Common pipeline shape:

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> ... handler-specific steps ...
  |> Step.audit()
  |> Step.effects(&compute_effects/2)   # OR Step.no_effects()
end
```

Reserved step names: `:envelope` (set by `Step.new/1`), `:audit` (set by `Step.audit/1`), `:effects` (set by `Step.effects/2` or `Step.no_effects/1`).

## Handler specs

### `AddGalleryToFamilyHandler`

> Story: add the gallery, audit.

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.insert(:gallery, &add_gallery_to_family/1)
  |> Step.audit()
  |> Step.no_effects()
end

defp add_gallery_to_family(%{envelope: envelope}) do
  %Gallery{} |> Gallery.changeset(Map.from_struct(envelope.command))
end
```

primary_step: `:gallery`

### `RemoveGalleryFromFamilyHandler`

> Story: find the gallery, remove it, audit.

```elixir
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
```

primary_step: `:gallery`

### `AddPhotoToGalleryHandler`

> Story: insert the photo, complete it by preloading its gallery, schedule transform-and-store, audit.

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.insert(:inserted_photo, &add_photo_to_gallery/1)
  |> Step.run(:photo, &preload_photo_gallery/2)
  |> Step.enqueue(:worker, &transform_and_store_photo/1)
  |> Step.audit()
  |> Step.no_effects()
end

defp add_photo_to_gallery(%{envelope: envelope}) do
  %Photo{} |> Photo.changeset(Map.from_struct(envelope.command))
end

defp preload_photo_gallery(repo, %{inserted_photo: photo}) do
  {:ok, repo.preload(photo, :gallery)}
end

defp transform_and_store_photo(%{photo: photo}) do
  TransformAndStorePhoto.new(%{photo_id: photo.id})
end
```

primary_step: `:photo`. No PubSub broadcast on insert — `TransformAndStorePhoto` worker emits `:photo_processed` after transform completes (current behavior).

### `RemovePhotoFromGalleryHandler`

> Story: find and remove the photo, audit, then clean up its storage post-commit.

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.run(:photo, &remove_photo/2)
  |> Step.audit()
  |> Step.effects(&clean_up_storage/2)
end

defp remove_photo(repo, %{envelope: envelope}) do
  case repo.get(Photo, envelope.command.photo_id) do
    nil -> {:error, :not_found}
    photo -> repo.delete(photo)
  end
end

defp clean_up_storage(_repo, %{photo: photo}) do
  if photo.image,
    do: {:ok, [{:waffle_delete, photo}]},
    else: {:ok, []}
end
```

primary_step: `:photo`. Dispatcher gains `run_effect({:waffle_delete, photo})` clause.

### `TagPersonInPhotoHandler`

> Story: tag the person in the photo (upsert).

```elixir
@upsert_opts [
  on_conflict: {:replace, [:x, :y]},
  conflict_target: [:photo_id, :person_id],
  returning: true
]

defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.insert(:photo_person, &tag_person_in_photo/1, @upsert_opts)
  |> Step.audit()
  |> Step.no_effects()
end

defp tag_person_in_photo(%{envelope: envelope}) do
  cmd = envelope.command
  PhotoPerson.changeset(
    %PhotoPerson{photo_id: cmd.photo_id, person_id: cmd.person_id},
    %{x: cmd.x, y: cmd.y}
  )
end
```

primary_step: `:photo_person`

### `UntagPersonFromPhotoHandler`

> Story: untag the person from the photo.

```elixir
defp to_transaction(envelope) do
  Step.new(envelope)
  |> Step.run(:tag, &untag_person_from_photo/2)
  |> Step.audit()
  |> Step.no_effects()
end

defp untag_person_from_photo(repo, %{envelope: envelope}) do
  cmd = envelope.command
  query =
    from pp in PhotoPerson,
      where: pp.photo_id == ^cmd.photo_id and pp.person_id == ^cmd.person_id

  {_count, _} = repo.delete_all(query)
  {:ok, :ok}
end
```

primary_step: `:tag` (atom `:ok`).

### `AddCommentToPhotoHandler` (rename + refactor)

> Story: insert the comment, complete it by preloading its account, audit, broadcast its creation.

```elixir
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
```

primary_step: `:comment` (was `:preloaded`).

### `UpdatePhotoCommentHandler` (refactor)

> Story: authorize the edit, update the text, complete it by preloading its account, audit, broadcast.

```elixir
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
```

primary_step: `:comment`.

### `RemoveCommentFromPhotoHandler` (rename + refactor)

> Story: authorize the deletion (load + owner-or-admin check, preload account), remove it, audit, broadcast.

```elixir
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
```

primary_step: `:comment`. Broadcast carries the preloaded version (`authorized_comment`) so subscribers retain account info.

## Command specs

| Command | Fields | Validation | Permission | Primary step |
|---|---|---|---|---|
| `AddGalleryToFamily` | `family_id, name` | `family_id` integer required; `name` string required, length 1..255 | `{:create, Gallery}` | `:gallery` |
| `RemoveGalleryFromFamily` | `gallery_id` | `gallery_id` integer required | `{:delete, Gallery}` | `:gallery` |
| `AddPhotoToGallery` | `gallery_id, original_path, original_filename, content_type, file_hash` | all strings required; `gallery_id` integer required | `{:create, Photo}` | `:photo` |
| `RemovePhotoFromGallery` | `photo_id` | `photo_id` integer required | `{:delete, Photo}` | `:photo` |
| `TagPersonInPhoto` | `photo_id, person_id, x, y` | `photo_id`/`person_id` integers required; `x, y` floats or nil; both set together; range [0.0, 1.0] | `{:update, Photo}` | `:photo_person` |
| `UntagPersonFromPhoto` | `photo_id, person_id` | both integers required | `{:update, Photo}` | `:tag` |
| `AddCommentToPhoto` | `photo_id, text` | required, text length max 5000 | `{:create, PhotoComment}` | `:comment` |
| `UpdatePhotoComment` | `photo_comment_id, text` | required, text length max 5000 | `{:update, PhotoComment}` | `:comment` |
| `RemoveCommentFromPhoto` | `photo_comment_id` | required integer | `{:delete, PhotoComment}` | `:comment` |

`Permission alignment` — current Permit rules cover all 9 commands without modification:

| Role | Gallery / Photo / PhotoComment | Effect |
|---|---|---|
| `:admin` | `all` | every command authorized |
| `:editor` | `all` | every command authorized; record-level rules enforced inline in handlers (comment update/delete) |
| `:viewer` | `read` (+ `create` on PhotoComment) | only `AddCommentToPhoto` reachable; everything else denied at dispatcher |

## Dispatcher refactor

```elixir
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

defp run_effect({:waffle_delete, %Photo{image: img} = photo}) when not is_nil(img),
  do: Ancestry.Uploaders.Photo.delete({img, photo})

defp run_effect({:waffle_delete, _}), do: :ok
```

`Behaviour change:`

```elixir
defmodule Ancestry.Bus.Handler do
  @callback handle(Ancestry.Bus.Envelope.t()) ::
              {:ok, map()}
              | {:error, atom() | tuple() | term(), term(), map()}
              | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Handler
    end
  end
end
```

## LiveView rewiring

All callsites switch from direct `Galleries.*` calls to `Ancestry.Bus.dispatch/2` and route results through the shared `Web.BusUI.handle_dispatch_result/2` helper.

### Shared helper (`Web.BusUI`)

```elixir
defmodule Web.BusUI do
  use Web, :verified_routes
  use Gettext, backend: Web.Gettext
  alias Phoenix.LiveView

  def handle_dispatch_result({:ok, _result}, socket), do: {:noreply, socket}

  def handle_dispatch_result({:error, :validation, changeset}, socket),
    do: {:noreply, LiveView.assign(socket, :form, Phoenix.Component.to_form(changeset))}

  def handle_dispatch_result({:error, :unauthorized}, socket),
    do: {:noreply, LiveView.put_flash(socket, :error, gettext("You don't have permission to do that."))}

  def handle_dispatch_result({:error, :not_found}, socket),
    do: {:noreply, LiveView.put_flash(socket, :error, gettext("That item no longer exists."))}

  def handle_dispatch_result({:error, :conflict, _term}, socket),
    do: {:noreply, LiveView.put_flash(socket, :error,
         gettext("That action conflicted with another change. Please retry."))}

  def handle_dispatch_result({:error, :handler, term}, socket) do
    require Logger
    Logger.error("command failed", error: inspect(term))
    {:noreply, LiveView.put_flash(socket, :error, gettext("Something went wrong."))}
  end
end
```

Auto-imported into all LiveViews/components via `lib/web.ex`. The local `defp handle_dispatch_result/2` clauses in `PhotoCommentsComponent` are removed in Phase 0.

### Photo upload pre-flight

```elixir
# in gallery_live/show.ex process_uploads/1
results =
  consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
    contents = File.read!(tmp_path)
    file_hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

    cond do
      Galleries.photo_exists_in_gallery?(gallery.id, file_hash) ->
        {:ok, {:duplicate, entry.client_name}}

      true ->
        original_path =
          Storage.store_original_bytes(
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

        case Bus.dispatch(socket.assigns.current_scope, AddPhotoToGallery.new!(attrs)) do
          {:ok, photo} -> {:ok, {:ok, photo}}
          {:error, _} -> {:ok, {:error, entry.client_name}}
        end
    end
  end)
```

Dedup runs before S3 store (cheap query first). On dispatch failure, the S3 original is left orphaned (accepted).

### Other rewires

- `family_live/show.ex` — `save_gallery` / `delete_gallery` events.
- `gallery_live/show.ex` — bulk photo delete, quick-create tag fan-out.
- `person_live/show.ex` — quick-create tag fan-out.
- `photo_interactions.ex` — `tag_person/4`, `untag_person/3`, `link_existing_person/2`.

Tag/untag UI continues to swallow errors silently (current behavior). Photo upload failures continue to surface as `{:error, name}` in the upload results modal.

## Testing strategy

Three layers, mirroring the photo-comment migration.

**Layer 1: Command unit tests** (`test/ancestry/commands/<name>_test.exs`, `async: true`).

Per command: `new/1` validation rules, `permission/0`, `primary_step/0`. ~5–8 tests per file.

**Layer 2: Handler integration tests** (`test/ancestry/handlers/<name>_handler_test.exs`, `async: false`).

Per handler:
- happy path: `handle/1` returns `{:ok, changes}` with the right primary step value, audit row written, effects fired.
- `Bus.dispatch/2` end-to-end: classified result, audit row, effects (PubSub broadcast / Waffle delete).
- `:not_found` for missing entities (delete + tag/untag).
- `:unauthorized` for handlers with record-level authz (comment update/delete only).
- validation failure → no audit row.

**Layer 3: User-flow tests** (`test/user_flows/<flow>_test.exs`).

| File | Covers |
|---|---|
| `gallery_create_test.exs` | `AddGalleryToFamily` via `family_live/show` |
| `gallery_delete_test.exs` | `RemoveGalleryFromFamily` (incl. cascade verification) |
| `photo_upload_test.exs` | `AddPhotoToGallery` via gallery upload, dedup, S3 pre-flight |
| `photo_delete_test.exs` | `RemovePhotoFromGallery` (incl. Waffle cleanup effect) |
| `photo_tag_test.exs` | `TagPersonInPhoto`, `UntagPersonFromPhoto` |

Each user-flow test asserts the user-visible outcome (DOM state, redirect, flash) AND a row in `audit_log` with the expected `command_module` and `payload`.

Existing tests requiring migration in Phase 0:

| File | Change |
|---|---|
| `test/ancestry/commands/create_photo_comment_test.exs` | rename, update module name |
| `test/ancestry/commands/delete_photo_comment_test.exs` | rename, update module name |
| `test/ancestry/handlers/create_photo_comment_handler_test.exs` | rename, update step names + assertions |
| `test/ancestry/handlers/delete_photo_comment_handler_test.exs` | rename, update step names + assertions |
| `test/ancestry/handlers/update_photo_comment_handler_test.exs` | update for split insert/preload pattern |
| `test/ancestry/bus_test.exs` | rename `:__audit__` → `:audit`, `:__effects__` → `:effects`. `build_multi/1` → `handle/1`. Replace inline lambdas with named test helpers. |
| `test/user_flows/photo_comments_*.exs` | update `command_module` strings post-rename |

`Ancestry.Bus.Step` itself: small unit test (`test/ancestry/bus/step_test.exs`) covering `new/1`, `audit/1`, `effects/1`, `no_effects/1`, `enqueue/3`.

## Implementation order

Four phases, all on the `commands` branch as a continuous sequence of commits.

### Phase 0 — Foundation cleanup

1. Create `Ancestry.Bus.Step`.
2. Update `Ancestry.Bus.Handler` behaviour: `build_multi/1` → `handle/1`.
3. Refactor `Ancestry.Bus` dispatcher: drop `:__audit__` prepend, rename effects key, switch handler invocation to `handle/1`, add `:waffle_delete` effect clause.
4. Promote `handle_dispatch_result/2` to `Web.BusUI`, auto-import via `lib/web.ex`.
5. Rename comment commands + handlers + tests:
   - `CreatePhotoComment` → `AddCommentToPhoto`
   - `DeletePhotoComment` → `RemoveCommentFromPhoto`
   - Refactor all three (incl. `UpdatePhotoComment`) to `handle/1` + `to_transaction/1` + `Step` DSL + story-driven step names + split insert/update from preload.
6. Rename `Ancestry.Workers.ProcessPhotoJob` → `Ancestry.Workers.TransformAndStorePhoto` (file, module, callsites).
7. Update `bus_test.exs`: step name renames, replace inline lambdas with named test helpers, switch to `handle/1`.
8. `mix precommit` — all existing tests pass.

Behavior preserved end-to-end. No user-visible changes.

### Phase 1 — Galleries

1. `AddGalleryToFamily` command + unit tests.
2. `AddGalleryToFamilyHandler` + integration tests.
3. `RemoveGalleryFromFamily` command + unit tests.
4. `RemoveGalleryFromFamilyHandler` + integration tests.
5. Rewire `family_live/show.ex` (`save_gallery`, `delete_gallery`).
6. New user-flow tests: `gallery_create_test.exs`, `gallery_delete_test.exs`.
7. Strip `Galleries.create_gallery/1` and `Galleries.delete_gallery/1`. Migrate any test callers to `insert(:gallery, ...)`.

### Phase 2 — Photos

1. `AddPhotoToGallery` command + unit tests.
2. `AddPhotoToGalleryHandler` + integration tests (incl. Oban enqueue assertion).
3. `RemovePhotoFromGallery` command + unit tests.
4. `RemovePhotoFromGalleryHandler` + integration tests (incl. `:waffle_delete` effect assertion).
5. Rewire `gallery_live/show.ex` (`process_uploads/1` pre-flight, `confirm_delete_photos`).
6. New user-flow tests: `photo_upload_test.exs`, `photo_delete_test.exs`.
7. Strip `Galleries.create_photo/1` and `Galleries.delete_photo/1`. Worker keeps `update_photo_processed/2` and `update_photo_failed/1`.

### Phase 3 — Tags

1. `TagPersonInPhoto` command + unit tests.
2. `TagPersonInPhotoHandler` + integration tests.
3. `UntagPersonFromPhoto` command + unit tests.
4. `UntagPersonFromPhotoHandler` + integration tests.
5. Rewire `photo_interactions.ex`, `gallery_live/show.ex` (quick-create branch), `person_live/show.ex` (quick-create branch).
6. New user-flow test: `photo_tag_test.exs`.
7. Strip `Galleries.tag_person_in_photo/4` and `Galleries.untag_person_from_photo/2`.

### Phase 4 — Final verification

1. `mix precommit` green; no warnings.
2. Verify `Ancestry.Galleries` is queries-only:
   - Public API: `list_*`, `get_*!`, `change_*`, `update_photo_processed/2`, `update_photo_failed/1` (worker-only), `photo_exists_in_gallery?/2`.
3. Manual smoke test in dev:
   - Create a gallery → audit row.
   - Upload a photo → audit row + Oban job + worker completion.
   - Tag/untag a person → 2 audit rows.
   - Delete the photo → audit row + S3 cleanup.
   - Delete the gallery → audit row + cascaded photos.
4. Inspect `audit_log` via Tidewave:
   ```sql
   SELECT command_module, count(*) FROM audit_log GROUP BY command_module;
   ```
   Expected: rows for all 6 + 3 commands.

## Open follow-ups (NOT in this plan)

- Auditing failures (validation, authz, exceptions) into a separate sink.
- Migrating other contexts (`Families`, `People`, `Identity`, `Memories`, `Relationships`, `Import`) through `Ancestry.Bus`.
- Worker-event audit sink for `update_photo_processed/2` / `update_photo_failed/1`.
- S3 lifecycle / orphan cleanup (gallery cascade leaves originals; create-then-fail leaves originals).
- Real-time `:photo_created` / `:photo_deleted` / `:tag_added` broadcasts for cross-client UI sync.
- Entity external IDs (`pho-<uuid>`, `gal-<uuid>`, etc.) and URL changes.
- Promoting handler-inline owner checks (currently in `UpdatePhotoCommentHandler`, `RemoveCommentFromPhotoHandler`) into Permit clauses if the installed Permit version supports record-level conditions.

## Notes for the executing engineer

- This plan extends `docs/plans/2026-05-07-command-handler-foundation.md` (the photo-comment migration). Read it first.
- `CLAUDE.md` — particularly the `Command/Handler Architecture (Bus)` and `Patterns to use in the project → Ecto` sections — is the source of truth for the conventions described here.
- Use `Ancestry.Bus.Step` exclusively in handler bodies. Never call `Multi.*` or `Oban.*` directly.
- Story-driven naming is non-negotiable: step names are nouns, function names are action verbs, no `_changeset` / `_attrs` / `_params` suffixes, no inline anonymous functions.
- Insert+preload always splits into two steps: `:inserted_<thing>` then `:<thing>`. Same for update.
- Use Tidewave (`get_ecto_schemas`, `get_source_location`, `project_eval`, `execute_sql_query`, `get_logs`) before guessing about runtime state.
- E2E tests must follow `test/user_flows/CLAUDE.md`: Given/When/Then comments, snake_case `_test.exs` files, exercise rendered templates with real data.
- After every code-touching task, `mix compile --warnings-as-errors` must pass before the commit step.
- Final phase runs `mix precommit`. Do not skip it.
