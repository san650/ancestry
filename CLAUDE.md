# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is a family photo gallery web application built with Phoenix LiveView.

**OTP app:** `:ancestry`

## Commands

- `mix setup` — install deps, create/migrate DB, seed default family, build assets
- `mix test` — run all tests (auto-creates/migrates test DB)
- `mix test test/path/to_test.exs` — run a single test file
- `mix test --failed` — re-run only previously failed tests
- `mix precommit` — compile (warnings-as-errors), remove unused deps, format, and run tests. **Run before finishing any task.**
- `iex -S mix phx.server` — start dev server

## Architecture

**Module naming:** The web layer is namespaced as `Web` (not `AncestryWeb`). This is intentional — `phx.new` was generated with `--module Web` to keep templates and aliases shorter. Business logic lives under `Ancestry.*`.

**Tenant model:** `Organization` is the top-level tenant. An organization has many `families`, a family has many `people` (via `family_members`) and many `galleries`, and a gallery has many `photos`. Most authenticated routes are scoped under `/org/:org_id/`.

```
lib/
  ancestry/                # Business logic (contexts, schemas, workers)
    organizations.ex       # Organizations context — top-level tenant
    organizations/organization.ex
    identity.ex            # Auth context — accounts, tokens, scopes
    identity/{account, account_token, account_notifier, scope}.ex
    families.ex            # Families context — CRUD for families + cover photos
    families/family.ex
    people.ex              # People context — persons and family memberships
    people/{person, family_member, person_tree}.ex
    relationships.ex       # Person-to-person relationships (parent, partner, etc.)
    relationships/relationship.ex
    relationships/metadata/  # Type-specific metadata embeds (married, divorced, parent, …)
    kinship.ex             # Bidirectional BFS to find MRCA + classify kinship
    galleries.ex           # Galleries context — photos and galleries API
    galleries/{gallery, photo}.ex
    comments.ex            # Photo comments
    comments/photo_comment.ex
    import.ex              # External-data import dispatcher
    import/csv/{adapter, family_echo}.ex
    storage.ex             # S3/local storage abstraction for original uploads
    string_utils.ex
    uploaders/             # Waffle uploaders (family_cover, person_photo, photo)
    workers/               # Oban jobs (process_{family_cover,person_photo,photo}_job)
  web/                     # Phoenix web layer (namespace: Web)
    live/
      account_live/        # Login, registration, settings, confirmation
      family_live/         # Index, New, Show
      gallery_live/        # Show
      person_live/         # Index, New, Show
      people_live/         # Family-scoped people index
      org_people_live/     # Organization-scoped people index
      organization_live/   # Organization index
      kinship_live.ex      # Kinship calculator
      comments/            # Photo comments component
      shared/              # person_form_component, add_relationship_component
    router.ex
```

> The list above is a snapshot. When in doubt, run `ls lib/ancestry/` and `ls lib/web/live/` — the source of truth is the filesystem.

**URL structure:** Routes live in `lib/web/router.ex`. Authenticated routes use a `live_session :organization` block scoped under `/org/:org_id/` with the `Web.EnsureOrganization` on_mount hook:

- `/` — landing page (public)
- `/accounts/log-in` — login (public)
- `/org` — organization picker
- `/org/:org_id` — family index for the organization
- `/org/:org_id/families/new` — new family form
- `/org/:org_id/families/:family_id` — family show
- `/org/:org_id/families/:family_id/galleries/:id` — gallery show with photos
- `/org/:org_id/families/:family_id/members/new` — add a new person to a family
- `/org/:org_id/families/:family_id/people` — people in a family
- `/org/:org_id/families/:family_id/kinship` — kinship calculator
- `/org/:org_id/people/:id` — person detail
- `/org/:org_id/people` — all people in the organization

**Important schema/table mismatches:** the `Person` schema maps to the `persons` table (not `people`), and `AccountToken` maps to `accounts_tokens`. Keep this in mind when writing raw SQL.

## Authentication

Auth is built on top of `phx.gen.auth`, with `Account` (not `User`) as the principal:

- `Ancestry.Identity` is the auth context. Schemas: `Account`, `AccountToken`, `Scope`. Notifier: `AccountNotifier`.
- `Web.AccountAuth` provides plugs (`fetch_current_scope_for_account`, `require_authenticated_account`) and `on_mount` callbacks (`:mount_current_scope`, `:require_authenticated`).
- `Web.EnsureOrganization` is the second `on_mount` hook used by every `/org/:org_id/...` route — it loads the organization into `current_scope` and authorises the account.
- All authenticated LiveViews receive `current_scope` in their assigns. **Always pass it to `<Layouts.app current_scope={@current_scope} ...>`** — `current_scope` errors mean a route is in the wrong `live_session` or is missing the assign in the layout.
- Account registration is currently commented out in `router.ex`; only login and email confirmation are wired up.

## Image processing

**Photo processing flow:**
1. User uploads via LiveView `allow_upload` (up to 10 files, 300MB each)
2. `consume_uploaded_entries` stores the original via `Ancestry.Storage.store_original/2` — in production this uploads directly to S3-compatible (S3), in dev it writes to `priv/static/uploads/originals/{uuid}/photo.ext`
3. An `Oban.Job` (`ProcessPhotoJob`, queue: `:photos`) is inserted
4. The job fetches the original via `Ancestry.Storage.fetch_original/1` (downloads from S3 to `/tmp` in prod, reads local path in dev), runs Waffle/ImageMagick to produce `:original`, `:large`, `:thumbnail` versions, and stores them via Waffle's S3 adapter (prod) or local storage (dev)
5. After processing, the job cleans up temp files and deletes the original from S3 (prod only)
6. On completion/failure, the job broadcasts `{:photo_processed, photo}` or `{:photo_failed, photo}` over PubSub topic `"gallery:{id}"`
7. The `GalleryLive.Show` LiveView subscribes to this topic and updates the stream

**Family cover processing flow:** Parallel to photo processing — uploading a cover image on `FamilyLive.Show` inserts a `ProcessFamilyCoverJob` (queue: `:photos`). On completion/failure, it broadcasts `{:cover_processed, family}` or `{:cover_failed, family}` over PubSub topic `"family:{id}"`.

**Photo statuses:** `"pending"` → `"processed"` or `"failed"`

**Storage abstraction (`Ancestry.Storage`):** Provides `store_original/2`, `fetch_original/1`, `cleanup_original/1`, and `delete_original/1`. Routes to S3 or local disk based on the `Waffle` storage config. All LiveViews and Oban workers use this module instead of direct filesystem operations.

**Key dependencies:** Oban (background jobs), Waffle + Waffle.Ecto (file uploads/storage), ExAws + ExAws.S3 (S3 client for S3-compatible), Phoenix PubSub (real-time updates)

## Production

**Image storage:** Production uses an S3-compatible object storage for all image uploads and processed versions.

**Configuration:** ExAws is configured in `config/prod.exs` with `{:system, "..."}` tuples. The production server's secrets provide:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — S3-compatible credentials (auto-set by the production server)
- `AWS_ENDPOINT_URL_S3` — S3-compatible endpoint (auto-set by the production server)
- `AWS_S3_BUCKET` — bucket name
- `AWS_REGION` — set to `auto`
- ASSET_HOST - public host for assets

**Runtime:** Dockerfile uses a multi-stage build with ImageMagick installed in the runner stage for Waffle transforms. Release command runs migrations (`/app/bin/migrate`).

## Genealogy & Kinship Terminology

**MANDATORY:** Consult `./GENEALOGY.md` for the complete coordinate-based kinship terminology mapping (English ↔ Spanish) whenever working on kinship labels, translations, or relationship naming. This file is the single source of truth for how `(steps_a, steps_b)` coordinates map to gendered labels in both languages, including the "removed cousin" → Tío/Sobrino conversion.

## UI/UX Graphical Design

MANDATORY: Use the design system and rules defined in ./DESIGN.md

## Plans and specs

**MANDATORY:** Save all design specs, brainstorming outputs, and implementation plans to `docs/plans/YYYY-MM-DD-<topic>.md`. This is the only location used for plans.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- **Learnings:** `docs/learnings.jsonl` contains structured lessons from past issues (one JSON object per line with `id`, `tags`, `title`, `problem`, `fix` fields). Grep by tag or keyword instead of reading the whole file:
  - `grep "liveview" docs/learnings.jsonl` — all LiveView-related learnings
  - `grep "js-hooks" docs/learnings.jsonl` — JS hook pitfalls
  - `grep "silent-failure" docs/learnings.jsonl` — bugs that fail without errors
  - `grep "testing" docs/learnings.jsonl` — test-related learnings
  - `grep "security" docs/learnings.jsonl` — security-related learnings
  - `docs/learnings.md` contains a human-readable index table of all learnings — consult it for a quick overview
  - After fixing a recurring issue or completing a recurring refactor, append a new entry to the JSONL file **and** update the index in `docs/learnings.md` to keep them in sync
- When writing a new feature use the elixir:elixir-thinking and elixir:phoenix-thinking skills

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `Web.Layouts` module is aliased in `lib/web.ex`, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

## Tidewave Phoenix

This project exposes Tidewave Phoenix MCP tools. **Always prefer Tidewave over grep, file inspection, or memory** when one of these tools can answer the question. Never invent module APIs, schema fields, routes, assigns, database columns, or runtime config — verify with Tidewave first.

| Tool | Use for |
|---|---|
| `get_ecto_schemas` | List schemas, fields, associations |
| `get_source_location` | Find where a module/function/macro is defined |
| `get_docs` | Read docs for installed modules/functions |
| `search_package_docs` | Search HexDocs scoped to this project's deps |
| `project_eval` | Run Elixir in the running app — validate runtime, config, macros, business logic |
| `execute_sql_query` | Inspect dev DB state (read queries unless writes are required) |
| `get_logs` | Check server logs after a request, LiveView interaction, or background job |

**Recommended workflow** when implementing or debugging:

1. `get_ecto_schemas` to discover the data model
2. `get_docs` / `search_package_docs` for framework or dependency questions
3. `get_source_location` to jump to definitions
4. `project_eval` to validate runtime assumptions
5. `execute_sql_query` to confirm persisted state
6. `get_logs` after running the flow

## Patterns to use in the project

### Ecto

- **Always** use Ecto.Multi if you're inserting, updating and/or deleting several schemas in the same operations with a transaction.

Don't do this

<bad-example>
def create_person(family, attrs) do
  Repo.transaction(fn ->
    case %Person{organization_id: family.organization_id}
         |> Person.changeset(attrs)
         |> Repo.insert() do
      {:ok, person} ->
        %FamilyMember{family_id: family.id, person_id: person.id}
        |> FamilyMember.changeset(%{})
        |> Repo.insert!()

        person

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end)
end
</bad-example>

Do this instead

<good-example>
alias Ecto.Multi

def create_person(family, attrs) do
  case do_create_person(family, attrs) do
    {:ok, %{person: person}} ->
      person 
    {:error, _failed_operation, failed_value, _changes_so_far} ->
      # The error tuple to return will depend on the use case.
      {:error, failed_value}
  end
end

defp do_create_person(family, attrs) do
  # We can see at a glance all the operations of the transaction
  # in a nice and compact way. Easier to add or remove operations
  # in the future.
  Multi.new()
  |> Multi.put(:family, family)
  |> Multi.put(:person_attrs, attrs) 
  |> Multi.insert(:person, &insert_person/1)
  |> Multi.insert(:family_member, &insert_family_member/1)
  |> Repo.transaction()
end

defp insert_person(%{family: family, person_attrs: attrs}) do
  %Person{}
  |> Person.changeset(Map.put(attrs, :organization_id, family.organization_id))
end

defp insert_family_member(%{family: family, person: person}) do
  %FamilyMember{}
  |> FamilyMember.changeset(%{family_id: family.id, person_id: person.id})
end
</good-example>

- **Always** extract Multi steps into named private functions. The Multi pipeline should read as a clear sequence of named steps — don't inline anonymous functions.

Don't do this

<bad-example>
Multi.new()
|> Multi.run(:check, fn repo, _changes ->
    # ... many lines of inlined logic ...
  end)
|> Multi.run(:process, fn repo, %{check: result} ->
    # ... more inlined logic ...
  end)
|> Repo.transaction()
</bad-example>

Do this instead

<good-example>
Multi.new()
|> Multi.put(:input, input)
|> Multi.run(:check, &run_check/2)
|> Multi.run(:process, &run_process/2)
|> Repo.transaction()

defp run_check(repo, %{input: input}) do
  # ...
end

defp run_process(repo, %{check: result}) do
  # ...
end
</good-example>

### Authorization (Permit)

Authorization is centralized through [Permit](https://hexdocs.pm/permit). The three modules are:

- `Ancestry.Permissions` — defines `can/1` rules by pattern-matching on `Scope`
- `Ancestry.Authorization` — ties Permit to the app
- `Ancestry.Actions` — auto-discovers `live_action`s from `Web.Router`

**Rules:**

- **Always** use `Ancestry.Permissions` (`can/1`) to define who can do what. Never scatter role checks like `account.role == :admin` across LiveViews, templates, or contexts.
- **Always** use `Permit.Phoenix.LiveView` in LiveViews that need authorization. It hooks into `on_mount` and enforces permissions automatically based on the `live_action`.
- **Always** use Permit's `can?/3` or `authorized?/3` helpers when checking permissions in templates or contexts — never check `current_scope.account.role` directly.

Don't do this

<bad-example>
# In a template — manually checking role
<%= if @current_scope && @current_scope.account && @current_scope.account.role == :admin do %>
  <.link navigate={~p"/admin/accounts"}>Manage accounts</.link>
<% end %>

# In a context — hardcoding role bypass
def account_has_org_access?(%Account{role: :admin}, _org_id), do: true
def account_has_org_access?(%Account{id: id}, org_id) do
  Repo.exists?(from ao in AccountOrganization,
    where: ao.account_id == ^id and ao.organization_id == ^org_id)
end
</bad-example>

Do this instead

<good-example>
# In Permissions — single source of truth
def can(%Scope{account: %Account{role: :admin}}) do
  permit()
  |> all(Account)
  |> all(Organization)
end

# In a template — use the authorization helper
<%= if can?(@current_scope, :index, Account) do %>
  <.link navigate={~p"/admin/accounts"}>Manage accounts</.link>
<% end %>

# In a LiveView — use Permit.Phoenix.LiveView
use Permit.Phoenix.LiveView,
  authorization_module: Ancestry.Authorization,
  resource_module: Account

def handle_unauthorized(_action, socket) do
  {:halt,
   socket
   |> put_flash(:error, "You don't have permission to access this page")
   |> push_navigate(to: ~p"/org")}
end
</good-example>

## Feature testing

Every new or changed user flow **must** have E2E tests in `test/user_flows/` covering **all use cases**: create, edit, delete, navigate, and any error states. Tests must exercise the actual rendered templates with real data (including preloaded associations) to catch runtime errors like missing fields or unloaded associations that compile-time checks miss. See [`test/user_flows/CLAUDE.md`](test/user_flows/CLAUDE.md) for conventions, file naming, and example Given/When/Then specs to model new tests on.
