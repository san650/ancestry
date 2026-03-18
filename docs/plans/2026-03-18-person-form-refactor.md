# Person Form Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract person create/edit form into a shared LiveComponent with progressive disclosure, date dropdowns, radio gender selector, and responsive right-aligned labels.

**Architecture:** A `Web.Shared.PersonFormComponent` LiveComponent owns form state (validate/save), receives `person`, `family`, `action`, and `uploads` from parent LiveViews. Parents (`PersonLive.New` and `PersonLive.Show`) become thin wrappers handling navigation and upload lifecycle.

**Tech Stack:** Phoenix LiveView, LiveComponent, Tailwind CSS, Ecto changesets

---

### Task 1: Create the PersonFormComponent skeleton

**Files:**
- Create: `lib/web/live/shared/person_form_component.ex`
- Create: `lib/web/live/shared/person_form_component.html.heex`

**Step 1: Create the LiveComponent module with update/2 and event handlers**

```elixir
defmodule Web.Shared.PersonFormComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person

  @extra_fields [:given_name_at_birth, :surname_at_birth, :nickname, :title, :suffix, :alternate_names]

  @impl true
  def update(assigns, socket) do
    person = assigns.person
    changeset = People.change_person(person)

    show_details =
      socket.assigns[:show_details] ||
        Enum.any?(@extra_fields, fn field ->
          val = Map.get(person, field)
          val != nil && val != "" && val != []
        end)

    {:ok,
     socket
     |> assign(:person, person)
     |> assign(:family, assigns.family)
     |> assign(:action, assigns.action)
     |> assign(:uploads, assigns.uploads)
     |> assign(:form, to_form(changeset))
     |> assign(:show_details, show_details)}
  end

  @impl true
  def handle_event("toggle_details", _, socket) do
    {:noreply, assign(socket, :show_details, true)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    params = invert_living_to_deceased(params)

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params =
      params
      |> invert_living_to_deceased()
      |> process_alternate_names()

    case socket.assigns.action do
      :new -> save_new(socket, params)
      :edit -> save_edit(socket, params)
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    send(self(), {:cancel_upload, ref})
    {:noreply, socket}
  end

  def handle_event("cancel", _, socket) do
    case socket.assigns.action do
      :new -> {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}
      :edit -> send(self(), {:cancel_edit}); {:noreply, socket}
    end
  end

  defp save_new(socket, params) do
    family = socket.assigns.family

    case People.create_person(family, params) do
      {:ok, person} ->
        send(self(), {:person_saved, person})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_edit(socket, params) do
    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        send(self(), {:person_saved, person})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp invert_living_to_deceased(params) do
    case Map.pop(params, "living") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "deceased", "false")
      {"false", params} -> Map.put(params, "deceased", "true")
      {_, params} -> params
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} -> params
      {"", params} -> params
      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end

  defp living_checked?(form) do
    val = form[:deceased].value
    !(val in ["true", true])
  end

  defp month_options do
    [
      {"Jan", "1"}, {"Feb", "2"}, {"Mar", "3"}, {"Apr", "4"},
      {"May", "5"}, {"Jun", "6"}, {"Jul", "7"}, {"Aug", "8"},
      {"Sep", "9"}, {"Oct", "10"}, {"Nov", "11"}, {"Dec", "12"}
    ]
  end

  defp day_options do
    Enum.map(1..31, fn d -> {to_string(d), to_string(d)} end)
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
```

**Step 2: Create the template with full form layout**

Create `lib/web/live/shared/person_form_component.html.heex` with the form structure matching the design doc mockups. The template should include:

- Photo section (file input + preview)
- Given names and Surname (always visible)
- Gender radio buttons (always visible)
- Birth date with day/month dropdowns and year number input (always visible)
- Living checkbox (always visible)
- Death date (conditional on living unchecked)
- "Add more details" link (hidden when `@show_details` is true)
- Expanded fields: given_name_at_birth, nickname, title/suffix side-by-side, surname_at_birth
- Alternate names textarea (expanded only)
- Action buttons (Create/Save + Cancel)

The template uses a CSS grid for right-aligned labels on desktop (`md:grid md:grid-cols-[10rem_1fr]`), collapsing to stacked on mobile.

```heex
<div>
  <.form
    for={@form}
    id="person-form"
    phx-target={@myself}
    phx-submit="save"
    phx-change="validate"
    multipart
  >
    <div class="space-y-4">
      <%!-- Photo --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-start">
        <label class="text-sm font-medium text-base-content md:text-right md:pt-2">Photo</label>
        <div>
          <div class="flex items-center gap-4">
            <%= if @action == :edit && @person.photo && @person.photo_status == "processed" && @uploads.photo.entries == [] do %>
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
                alt="Current photo"
                class="w-16 h-16 rounded-lg object-cover"
              />
            <% end %>
            <.live_file_input upload={@uploads.photo} class="file-input file-input-bordered file-input-sm w-full max-w-xs" />
          </div>

          <%= for entry <- @uploads.photo.entries do %>
            <div class="mt-3 flex items-center gap-3">
              <.live_img_preview entry={entry} class="w-16 h-16 rounded-lg object-cover" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{entry.client_name}</p>
                <div class="mt-1 h-1.5 bg-base-200 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-primary rounded-full transition-all duration-300"
                    style={"width: #{entry.progress}%"}
                  />
                </div>
              </div>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-target={@myself}
                phx-value-ref={entry.ref}
                class="p-1.5 rounded-lg text-base-content/30 hover:text-error hover:bg-error/10 transition-all"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
          <% end %>

          <%= for err <- upload_errors(@uploads.photo) do %>
            <p class="text-error text-sm mt-2">{upload_error_to_string(err)}</p>
          <% end %>
        </div>
      </div>

      <%!-- Given names --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
        <label for={@form[:given_name].id} class="text-sm font-medium text-base-content md:text-right">
          Given names
        </label>
        <.input field={@form[:given_name]} label="" />
      </div>

      <%!-- Expanded: Given names at birth --%>
      <%= if @show_details do %>
        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
          <label for={@form[:given_name_at_birth].id} class="text-sm font-medium text-base-content md:text-right">
            Given names at birth
          </label>
          <.input field={@form[:given_name_at_birth]} label="" />
        </div>

        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
          <label for={@form[:nickname].id} class="text-sm font-medium text-base-content md:text-right">
            Nickname
          </label>
          <.input field={@form[:nickname]} label="" />
        </div>

        <%!-- Title and Suffix side by side --%>
        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
          <label class="text-sm font-medium text-base-content md:text-right">Title / Suffix</label>
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:title]} label="" placeholder="e.g. Dr., Sir" />
            <.input field={@form[:suffix]} label="" placeholder="e.g. Jr., III" />
          </div>
        </div>
      <% end %>

      <%!-- Surname --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
        <label for={@form[:surname].id} class="text-sm font-medium text-base-content md:text-right">
          Surname
        </label>
        <.input field={@form[:surname]} label="" />
      </div>

      <%!-- Expanded: Surname at birth --%>
      <%= if @show_details do %>
        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
          <label for={@form[:surname_at_birth].id} class="text-sm font-medium text-base-content md:text-right">
            Surname at birth
          </label>
          <.input field={@form[:surname_at_birth]} label="" />
        </div>
      <% end %>

      <%!-- Gender radio buttons --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
        <label class="text-sm font-medium text-base-content md:text-right">Gender</label>
        <div class="flex items-center gap-6">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="female"
              checked={to_string(@form[:gender].value) == "female"}
              class="radio radio-sm"
            />
            <span class="text-sm">Female</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="male"
              checked={to_string(@form[:gender].value) == "male"}
              class="radio radio-sm"
            />
            <span class="text-sm">Male</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="other"
              checked={to_string(@form[:gender].value) == "other"}
              class="radio radio-sm"
            />
            <span class="text-sm">Other</span>
          </label>
        </div>
      </div>

      <%!-- Birth date --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
        <label class="text-sm font-medium text-base-content md:text-right">Birth date</label>
        <div class="flex items-center gap-2">
          <select name={@form[:birth_day].name} id={@form[:birth_day].id} class="select select-bordered select-sm w-20">
            <option value="">Day</option>
            <%= for {label, val} <- day_options() do %>
              <option value={val} selected={to_string(@form[:birth_day].value) == val}>{label}</option>
            <% end %>
          </select>
          <select name={@form[:birth_month].name} id={@form[:birth_month].id} class="select select-bordered select-sm w-24">
            <option value="">Month</option>
            <%= for {label, val} <- month_options() do %>
              <option value={val} selected={to_string(@form[:birth_month].value) == val}>{label}</option>
            <% end %>
          </select>
          <input
            type="number"
            name={@form[:birth_year].name}
            id={@form[:birth_year].id}
            value={@form[:birth_year].value}
            min="1000"
            max="2100"
            placeholder="Year"
            class="input input-bordered input-sm w-24"
          />
        </div>
      </div>

      <%!-- Living checkbox --%>
      <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
        <div></div>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="hidden"
            name="person[living]"
            value="false"
          />
          <input
            type="checkbox"
            name="person[living]"
            id="person-living"
            value="true"
            checked={living_checked?(@form)}
            class="checkbox checkbox-sm"
          />
          <span class="text-sm">This person is living</span>
        </label>
      </div>

      <%!-- Death date (only if not living) --%>
      <%= unless living_checked?(@form) do %>
        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
          <label class="text-sm font-medium text-base-content md:text-right">Death date</label>
          <div class="flex items-center gap-2">
            <select name={@form[:death_day].name} id={@form[:death_day].id} class="select select-bordered select-sm w-20">
              <option value="">Day</option>
              <%= for {label, val} <- day_options() do %>
                <option value={val} selected={to_string(@form[:death_day].value) == val}>{label}</option>
              <% end %>
            </select>
            <select name={@form[:death_month].name} id={@form[:death_month].id} class="select select-bordered select-sm w-24">
              <option value="">Month</option>
              <%= for {label, val} <- month_options() do %>
                <option value={val} selected={to_string(@form[:death_month].value) == val}>{label}</option>
              <% end %>
            </select>
            <input
              type="number"
              name={@form[:death_year].name}
              id={@form[:death_year].id}
              value={@form[:death_year].value}
              min="1000"
              max="2100"
              placeholder="Year"
              class="input input-bordered input-sm w-24"
            />
          </div>
        </div>
      <% end %>

      <%!-- Add more details link --%>
      <%= unless @show_details do %>
        <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4">
          <div></div>
          <button
            type="button"
            id="add-more-details-btn"
            phx-click="toggle_details"
            phx-target={@myself}
            class="text-sm text-primary/60 hover:text-primary underline cursor-pointer transition-colors"
          >
            Add more details
          </button>
        </div>
      <% end %>

      <%!-- Alternate names (expanded only) --%>
      <%= if @show_details do %>
        <div class="border-t border-base-300 pt-4 mt-4">
          <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-start">
            <label for="person-alternate-names" class="text-sm font-medium text-base-content md:text-right md:pt-2">
              Alternate names
            </label>
            <div>
              <p class="text-xs text-base-content/50 mb-2">Also known as (one per line)</p>
              <textarea
                name="person[alternate_names_text]"
                id="person-alternate-names"
                rows="3"
                class="textarea textarea-bordered w-full"
                phx-debounce="300"
              ><%= if @action == :edit, do: Enum.join(@person.alternate_names, "\n") %></textarea>
            </div>
          </div>
        </div>
      <% end %>
    </div>

    <%!-- Action buttons --%>
    <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 mt-8">
      <div></div>
      <div class="flex gap-3">
        <button type="submit" id="person-form-submit" class="btn btn-primary flex-1">
          {if @action == :new, do: "Create", else: "Save"}
        </button>
        <button type="button" id="person-form-cancel" phx-click="cancel" phx-target={@myself} class="btn btn-ghost flex-1">
          Cancel
        </button>
      </div>
    </div>
  </.form>
</div>
```

**Step 3: Verify the component compiles**

Run: `mix compile --warnings-as-errors`
Expected: PASS (no references to this component yet, so it just needs to compile cleanly)

**Step 4: Commit**

```bash
git add lib/web/live/shared/person_form_component.ex lib/web/live/shared/person_form_component.html.heex
git commit -m "Add PersonFormComponent with progressive disclosure form"
```

---

### Task 2: Integrate component into PersonLive.New

**Files:**
- Modify: `lib/web/live/person_live/new.ex`
- Modify: `lib/web/live/person_live/new.html.heex`

**Step 1: Simplify the LiveView module**

Replace `new.ex` — remove all form event handlers (`validate`, `save`, `cancel_upload`), remove `process_alternate_names`, `maybe_process_photo`, and `upload_error_to_string`. Add `handle_info` for messages from the component.

```elixir
defmodule Web.PersonLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, %Person{})
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:person_saved, person}, socket) do
    socket = maybe_process_photo(socket, person)
    {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}
  end

  def handle_info({:cancel_upload, ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end
end
```

**Step 2: Update the template to use the component**

Replace `new.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/families/#{@family.id}"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">New Member</h1>
      </div>
    </div>
  </:toolbar>

  <div class="max-w-2xl mx-auto mt-8">
    <.live_component
      module={Web.Shared.PersonFormComponent}
      id="person-form"
      person={@person}
      family={@family}
      action={:new}
      uploads={@uploads}
    />
  </div>
</Layouts.app>
```

**Step 3: Run existing tests**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: Tests may need updates since the form ID changed from `#new-person-form` to `#person-form`

**Step 4: Update tests if needed**

In `test/web/live/person_live/new_test.exs`, update form selectors from `#new-person-form` to `#person-form`:

```elixir
defmodule Web.PersonLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "renders new person form", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/new")
    assert html =~ "New Member"
  end

  test "creates a person and redirects to family page", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane", surname: "Doe", gender: "female"})
    |> render_submit()

    assert_redirect(view, ~p"/families/#{family.id}")
  end

  test "validates form on change", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    view
    |> form("#person-form", person: %{given_name: "Jane"})
    |> render_change()

    assert has_element?(view, "#person-form")
  end
end
```

**Step 5: Run tests**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/web/live/person_live/new.ex lib/web/live/person_live/new.html.heex test/web/live/person_live/new_test.exs
git commit -m "Integrate PersonFormComponent into PersonLive.New"
```

---

### Task 3: Integrate component into PersonLive.Show (edit mode)

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Remove form-related event handlers from show.ex**

Remove from `show.ex`:
- `handle_event("validate", ...)` — component handles this
- `handle_event("save", ...)` — component handles this
- `handle_event("cancel_upload", ...)` — component handles via message
- `process_alternate_names/1` — moved to component
- `upload_error_to_string/1` — moved to component

Add new `handle_info` clauses:

```elixir
def handle_info({:person_saved, person}, socket) do
  socket = maybe_process_photo(socket, person)

  {:noreply,
   socket
   |> assign(:person, person)
   |> assign(:editing, false)
   |> assign(:form, to_form(People.change_person(person)))}
end

def handle_info({:cancel_upload, ref}, socket) do
  {:noreply, cancel_upload(socket, :photo, ref)}
end

def handle_info({:cancel_edit}, socket) do
  {:noreply, assign(socket, :editing, false)}
end
```

Keep `maybe_process_photo/2` in show.ex (it still needs to consume uploads from the parent LiveView).

Remove the `@form` assign from mount (the component manages its own form state). Keep `allow_upload`.

**Step 2: Update the template edit section**

In `show.html.heex`, replace the entire `<%= if @editing do %>` block (lines 37-173 approximately) with:

```heex
<%= if @editing do %>
  <div class="max-w-2xl mx-auto">
    <.live_component
      module={Web.Shared.PersonFormComponent}
      id="person-form"
      person={@person}
      family={@family}
      action={:edit}
      uploads={@uploads}
    />
  </div>
<% else %>
```

The rest of the template (detail view, relationships, modals) stays unchanged.

**Step 3: Run existing tests**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: Tests may need form selector updates from `#edit-person-form` to `#person-form`

**Step 4: Update tests if needed**

In `test/web/live/person_live/show_test.exs`, update the edit test's form selector:

```elixir
test "edits person name", %{conn: conn, family: family, person: person} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
  view |> element("#edit-person-btn") |> render_click()

  view
  |> form("#person-form", person: %{given_name: "Janet"})
  |> render_submit()

  assert render(view) =~ "Janet"
end
```

**Step 5: Run all person-related tests**

Run: `mix test test/web/live/person_live/`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex test/web/live/person_live/show_test.exs
git commit -m "Integrate PersonFormComponent into PersonLive.Show edit mode"
```

---

### Task 4: Add tests for new form features

**Files:**
- Modify: `test/web/live/person_live/new_test.exs`

**Step 1: Write tests for progressive disclosure**

Add tests to `new_test.exs`:

```elixir
test "compact form shows only basic fields", %{conn: conn, family: family} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

  assert has_element?(view, "#person_given_name")
  assert has_element?(view, "#person_surname")
  assert has_element?(view, "#add-more-details-btn")
  refute has_element?(view, "#person_nickname")
  refute has_element?(view, "#person_title")
  refute has_element?(view, "#person-alternate-names")
end

test "clicking add more details expands the form", %{conn: conn, family: family} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

  view |> element("#add-more-details-btn") |> render_click()

  assert has_element?(view, "#person_nickname")
  assert has_element?(view, "#person_title")
  assert has_element?(view, "#person_suffix")
  assert has_element?(view, "#person_given_name_at_birth")
  assert has_element?(view, "#person_surname_at_birth")
  assert has_element?(view, "#person-alternate-names")
  refute has_element?(view, "#add-more-details-btn")
end
```

**Step 2: Write tests for date dropdowns**

```elixir
test "birth date has day and month dropdowns", %{conn: conn, family: family} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

  assert has_element?(view, "select[name='person[birth_day]']")
  assert has_element?(view, "select[name='person[birth_month]']")
  assert has_element?(view, "input[name='person[birth_year]'][type='number']")
end
```

**Step 3: Write test for gender radio buttons**

```elixir
test "gender field uses radio buttons", %{conn: conn, family: family} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

  assert has_element?(view, "input[type='radio'][name='person[gender]'][value='female']")
  assert has_element?(view, "input[type='radio'][name='person[gender]'][value='male']")
  assert has_element?(view, "input[type='radio'][name='person[gender]'][value='other']")
end
```

**Step 4: Write test for living/deceased checkbox**

```elixir
test "living checkbox controls death date visibility", %{conn: conn, family: family} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

  # Living is checked by default, death date hidden
  refute has_element?(view, "select[name='person[death_day]']")

  # Uncheck living — death date should appear
  view
  |> form("#person-form", person: %{})
  |> render_change(%{"person" => %{"living" => "false"}})

  assert has_element?(view, "select[name='person[death_day]']")
end
```

**Step 5: Run tests**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add test/web/live/person_live/new_test.exs
git commit -m "Add tests for form progressive disclosure, date dropdowns, and radio gender"
```

---

### Task 5: Add tests for edit form auto-expand

**Files:**
- Modify: `test/web/live/person_live/show_test.exs`

**Step 1: Write test for auto-expand on edit**

```elixir
test "edit form auto-expands when person has extra fields", %{conn: conn, family: family} do
  {:ok, person_with_nickname} =
    People.create_person(family, %{
      given_name: "Maria",
      surname: "Silva",
      nickname: "Mari",
      gender: "female"
    })

  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person_with_nickname.id}")
  view |> element("#edit-person-btn") |> render_click()

  # Form should be auto-expanded since nickname has a value
  assert has_element?(view, "#person_nickname")
  refute has_element?(view, "#add-more-details-btn")
end

test "edit form shows compact when person has only basic fields", %{
  conn: conn,
  family: family,
  person: person
} do
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
  view |> element("#edit-person-btn") |> render_click()

  # Person only has given_name, surname, gender — should be compact
  assert has_element?(view, "#add-more-details-btn")
  refute has_element?(view, "#person_nickname")
end
```

**Step 2: Run tests**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: PASS

**Step 3: Commit**

```bash
git add test/web/live/person_live/show_test.exs
git commit -m "Add tests for edit form auto-expand behavior"
```

---

### Task 6: Run full precommit check

**Step 1: Run precommit**

Run: `mix precommit`
Expected: PASS — compilation with warnings-as-errors, format check, all tests pass

**Step 2: Fix any issues**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "Fix precommit issues from person form refactor"
```
