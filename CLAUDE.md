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

**Module naming:** The web layer uses `Web` (not `AncestryWeb`) as the module namespace. Business logic lives under `Ancestry.*`.

```
lib/
  ancestry/           # Business logic (contexts, schemas, workers)
    families.ex       # Families context — CRUD for families + cover photos
    families/
      family.ex       # Family schema (tenant entity, has_many galleries)
    galleries.ex      # Galleries context — primary public API for photos and galleries
    galleries/
      gallery.ex      # Gallery schema (belongs_to family)
      photo.ex        # Photo schema (uses Waffle.Ecto for file attachments)
    storage.ex        # S3/local storage abstraction for original uploads
    uploaders/
      family_cover.ex # Waffle uploader — produces :original, :thumbnail for family cover photos
      photo.ex        # Waffle uploader — produces :original, :large, :thumbnail versions via ImageMagick
    workers/
      process_family_cover_job.ex  # Oban job for family cover image processing
      process_photo_job.ex         # Oban job that runs ImageMagick and broadcasts via PubSub
  web/                # Phoenix web layer
    live/
      family_live/    # FamilyLive.Index, FamilyLive.New, FamilyLive.Show
      gallery_live/   # GalleryLive.Index and GalleryLive.Show
    router.ex
```

**URL structure:** All routes are nested under families:
- `/` — family index (homepage)
- `/families/new` — create a new family
- `/families/:family_id` — family detail page
- `/families/:family_id/galleries` — galleries for a family
- `/families/:family_id/galleries/:id` — gallery detail with photos

**Family as tenant:** Family is the top-level entity. Galleries belong to a family, and photos belong to a gallery. All gallery routes are scoped under `/families/:family_id/`.

**Photo processing flow:**
1. User uploads via LiveView `allow_upload` (up to 10 files, 300MB each)
2. `consume_uploaded_entries` stores the original via `Ancestry.Storage.store_original/2` — in production this uploads directly to Tigris (S3), in dev it writes to `priv/static/uploads/originals/{uuid}/photo.ext`
3. An `Oban.Job` (`ProcessPhotoJob`, queue: `:photos`) is inserted
4. The job fetches the original via `Ancestry.Storage.fetch_original/1` (downloads from S3 to `/tmp` in prod, reads local path in dev), runs Waffle/ImageMagick to produce `:original`, `:large`, `:thumbnail` versions, and stores them via Waffle's S3 adapter (prod) or local storage (dev)
5. After processing, the job cleans up temp files and deletes the original from S3 (prod only)
6. On completion/failure, the job broadcasts `{:photo_processed, photo}` or `{:photo_failed, photo}` over PubSub topic `"gallery:{id}"`
7. The `GalleryLive.Show` LiveView subscribes to this topic and updates the stream

**Family cover processing flow:** Parallel to photo processing — uploading a cover image on `FamilyLive.Show` inserts a `ProcessFamilyCoverJob` (queue: `:photos`). On completion/failure, it broadcasts `{:cover_processed, family}` or `{:cover_failed, family}` over PubSub topic `"family:{id}"`.

**Photo statuses:** `"pending"` → `"processed"` or `"failed"`

**Storage abstraction (`Ancestry.Storage`):** Provides `store_original/2`, `fetch_original/1`, `cleanup_original/1`, and `delete_original/1`. Routes to S3 or local disk based on the `Waffle` storage config. All LiveViews and Oban workers use this module instead of direct filesystem operations.

**Key dependencies:** Oban (background jobs), Waffle + Waffle.Ecto (file uploads/storage), ExAws + ExAws.S3 (S3 client for Tigris), Phoenix PubSub (real-time updates)

## Production (Fly.io)

**Deployment:** Deploys to Fly.io from `main` via GitHub Actions (`.github/workflows/fly-deploy.yml`). Primary region: `gru` (São Paulo). Uses `fly deploy --remote-only`.

**Image storage:** Production uses [Tigris](https://www.tigrisdata.com/) (Fly's S3-compatible object storage) for all image uploads and processed versions. The bucket is public (no signed URLs). Images are served directly from Tigris at `https://<bucket>.fly.storage.tigris.dev/...`.

**Configuration:** ExAws is configured in `config/prod.exs` with `{:system, "..."}` tuples. Fly secrets provide:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — Tigris credentials (auto-set by `fly storage create`)
- `AWS_ENDPOINT_URL_S3` — Tigris endpoint (auto-set by `fly storage create`)
- `AWS_S3_BUCKET` — bucket name
- `AWS_REGION` — set to `auto`

**Runtime:** Dockerfile uses a multi-stage build with ImageMagick installed in the runner stage for Waffle transforms. Release command runs migrations (`/app/bin/migrate`).

## Graphical Design

MANDATORY: Use the design system and rules defined in ./DESIGN.md

## Plans and specs

**MANDATORY:** All design specs, brainstorming outputs, and implementation plans MUST be saved to `docs/plans/`. Do not use `docs/superpowers/specs/` or any other location. When using the brainstorming skill, write the design document to `docs/plans/YYYY-MM-DD-<topic>.md`.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Read the document `doc/learnings.md` file to gather previous information about recurrent issues to avoid them
- When writing a new feature use the elixir:elixir-thinking and elixir:phoenix-thinking skills

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

## Tidewave Phoenix

This project exposes Tidewave Phoenix MCP tools. Prefer Tidewave tools over guessing, raw grep, or manual inspection whenever possible.

### Use these Tidewave tools first

- `get_docs`
  - Use for Elixir/Phoenix/Ecto/LiveView docs for modules, functions, and dependencies actually installed in this project.
  - Prefer this over general web search for library usage inside the app.
  - Examples
    - `get_docs Oban.Job.new/1` get package documentation for the function
    - `get_docs Ecto.Schema` get package documentation for the module

- `get_source_location`
  - Use to locate the source of modules/functions/macros quickly.
  - Prefer this before broad codebase searches when trying to find where something is defined.
  - Examples
    - `get_source_location Ancestry.People` get the exact file and line number where the module is defined
    - `get_source_location Ancestry.People.Person.changeset/2` get the exact file and line number where the function is defined


- `get_ecto_schemas`
  - Use when working with Ecto schemas, associations, fields, or database-backed domain modeling.
  - Prefer this before inferring schema structure from scattered files.
  - Only available when the project uses Ecto.
  - Examples
    - `get_ecto_schemas` list all schemas defined in the project

- `execute_sql_query`
  - Use to inspect development database state, validate assumptions, and confirm the effect of changes.
  - Prefer read queries unless the task explicitly requires writes.
  - Examples
    -`execute_sql_query "SELECT * FROM persons"` execute the SQL query in the development database

- `project_eval`
  - Use to evaluate Elixir code inside the running application context.
  - Prefer this for checking runtime behavior, inspecting modules, testing expressions, calling app functions, and validating business logic.
  - Use this instead of guessing how macros, config, or runtime wiring behave.
  - Examples 
    - `project_evel "Ancestry.Repo.all(Ancestry.People.Person)"` get all the people structs from the db

- `get_logs`
  - Use to inspect server logs after requests, LiveView interactions, background jobs, or runtime failures.
  - Always check logs when behavior differs from expectations.
  - Examples
    - `get_logs level: DEBUG, tail: 10` get the last 10 logs with DEBUG level or higher
    - `get_logs tail: 10, grep: QUERY` get the last 10 logs containing the word "QUERY"

- `search_package_docs`
  - Use to search HexDocs constrained to the exact dependencies in this project.
  - Prefer this over broad documentation search when looking for dependency APIs.
  - Examples
    - `search_package_docs insert!/3` search documentation for insert/3 function across all project dependencies

### Expected workflow

When implementing or debugging features in this Phoenix app, prefer this order:

1. Discover relevant modules with `get_ecto_schemas`
2. Read dependency or framework docs with `get_docs` or `search_package_docs`.
3. Find definitions with `get_source_location`.
4. Validate runtime assumptions with `project_eval`.
5. Inspect persisted data with `execute_sql_query`.
6. Check `get_logs` after running flows that hit the server.

### Phoenix-specific guidance

- For routes, controllers, LiveViews, components, contexts, schemas, and changesets, use Tidewave before making assumptions.
- For Ecto queries, schema fields, and associations, validate with `get_ecto_schemas`, `project_eval`, and `execute_sql_query`.
- For LiveView or request issues, inspect `get_logs` after reproducing the flow.
- For dependency usage, prefer `get_docs` and `search_package_docs` over memory.

### Rules

- Do not invent module APIs, schema fields, routes, assigns, or database columns when Tidewave can verify them.
- Do not assume runtime configuration or macro expansion details; verify with `project_eval`.
- Do not assume database contents; verify with `execute_sql_query`.
- If a Tidewave tool can answer the question, use it before falling back to generic search.

## Feature testing

When creating a new feature or fixing an existing feature make sure there is a test that covers the new/edited user flow to make sure there are no regression on the features. The main focus is to test using interactions.

Store this tests in the `test/user_flows/` folder. E.g. `test/user_flows/create-new-family.eex`.

To decide between LiveView tests and or e2e test have into account if the functionality is using javascript which can't be tested with LiveView tests. Prefer e2e tests where possible.

For each test for a user flow write a Given/When/Then comment on top of the test and then make sure the test follows all the specifications. If a feature changes a feature, update the Given/When/Then instructions and update the tests accordingly. Evaluate if it's better to add a new test or extend an existing test. The decision should be based on how related is the new functionality to any of the existing tests and how large the test already is. Accept large tests of a maximum of ~1000 lines.

The description of the tests use the Given/When/Then format. Below are some examples of test specifications you have to build for the application. Think on the test cases before writing these tests and don't mind if there is a bit of superposition between the tests (doesn't matter if several test test the same part of the application whenever it makes sense from a user flow stand of point).

Creating a new family
<test_case>
Given a system with no data
When the user clicks "New Family"
Then the "New Family" form is displayed.

When the user writes a name for the family
And selects a cover photo
And clicks "Create"
Then a new family is created
And the application navigates automatically to the family show page
And the empty state is shown

When the user clicks the navigate back arrow in the gallery
Then the grid with the list of families is shown

When the user clicks on the family shown in the grid
Then the user can see the family show page
</test_case>
Makes sure that all navigation and modals work as expected.

Edit family metadata
<test_case>
Given a family
When the user clicks on the family from the /families page
Then the user navigates to the family show page

When the user clicks "Edit" on the toolbar
Then a modal is shown to edit the family name

When the user enters a new family name in the modal
And clicks "Save"
Then the modal closes and the gallery show page is visible
And the gallery name is updated
</test_case>
Makes sure that all navigation and modals work as expected.

Delete family
<test_case>
Given a family with some people and galleries
When the user clicks on the family from the /families page
Then the user navigates to the family show page

When the user clicks "Delete" on the toolbar
Then a confirmation modal is shown

When the user clicks "Delete"
Then the gallery is deleted with all it's related galleries
And people is not deleted, just detached from the gallery
And the user is redirected to the /galleries page
</test_case>
Makes sure that all navigation and modals work as expected.

Creating people in a family
<test_case>
Given an existing family
When the user navigates to /families
And clicks on the existing family
Then the family show screen is shown
And the empty state can be seen

When the user clicks the add person button
Then the page navigates to the new member page

When the user fills the form with the user information
And uploads a photo for the user
And clicks "Create"
Then the page navigates to the family show page
And the new person is listed on the sidebar
</test_case>
Makes sure that all navigation and modals work as expected.

Linking people in a family
<test_case>
Given an existing family
And an existing person that's not associated to the family
When the user navigates to /families
And clicks on the existing family
Then the family show screen is shown
And the empty state can be seen

When the user clicks the link people
Then a modal is shown to search for an existing person

When the user search the existing user in the search form
Then the user appears as an option

When the user selects the person from the search form
Then the person is added to the family
And the page navigates to the family show page
And the new person is listed on the sidebar
</test_case>
Makes sure that all navigation and modals work as expected.
