# Tree View: Add Relationships In-Place — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users add partners, children, and parents directly from the tree view via an inline modal, reusing the same search-or-create flow that exists on the person detail page.

**Architecture:** Extract the add-relationship modal (search + quick-create + metadata) from `PersonLive.Show` into a shared LiveComponent (`Web.Shared.AddRelationshipComponent`). Both `FamilyLive.Show` and `PersonLive.Show` mount this component. Placeholder cards in the tree become buttons that open the modal instead of navigating away.

**Tech Stack:** Phoenix LiveView, LiveComponent, Ecto, Tailwind CSS

---

### Task 1: Create `Web.Shared.AddRelationshipComponent`

This is the core extraction. The new LiveComponent absorbs all modal logic currently split across `PersonLive.Show` event handlers and `QuickCreateComponent`.

**Files:**
- Create: `lib/web/live/shared/add_relationship_component.ex`

**Step 1: Create the shared component**

```elixir
defmodule Web.Shared.AddRelationshipComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:person, assigns.person)
     |> assign(:family, assigns.family)
     |> assign(:relationship_type, assigns.relationship_type)
     |> assign(:partner_id, assigns[:partner_id])
     |> assign_new(:step, fn -> :search end)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:search_results, fn -> [] end)
     |> assign_new(:selected_person, fn -> nil end)
     |> assign_new(:relationship_form, fn -> nil end)
     |> assign_new(:person_form, fn ->
       to_form(People.change_person(%Person{}), as: :person)
     end)}
  end

  # --- Search step ---

  @impl true
  def handle_event("search_members", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        People.search_family_members(
          query,
          socket.assigns.family.id,
          socket.assigns.person.id
        )
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("select_person", %{"id" => person_id}, socket) do
    selected = People.get_person!(person_id)
    type = socket.assigns.relationship_type

    relationship_form = build_relationship_form(type, selected)

    {:noreply,
     socket
     |> assign(:step, :metadata)
     |> assign(:selected_person, selected)
     |> assign(:relationship_form, relationship_form)}
  end

  def handle_event("start_quick_create", _, socket) do
    {:noreply, assign(socket, :step, :quick_create)}
  end

  def handle_event("cancel_quick_create", _, socket) do
    {:noreply, assign(socket, :step, :search)}
  end

  # --- Quick create step ---

  def handle_event("validate_person", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :person_form, to_form(changeset, as: :person))}
  end

  def handle_event("save_person", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Ecto.Changeset.validate_required([:given_name])

    if changeset.valid? do
      case People.create_person(socket.assigns.family, params) do
        {:ok, person} ->
          person = People.get_person!(person.id)
          type = socket.assigns.relationship_type
          relationship_form = build_relationship_form(type, person)

          {:noreply,
           socket
           |> assign(:step, :metadata)
           |> assign(:selected_person, person)
           |> assign(:relationship_form, relationship_form)}

        {:error, changeset} ->
          {:noreply, assign(socket, :person_form, to_form(changeset, as: :person))}
      end
    else
      {:noreply,
       assign(socket, :person_form, to_form(%{changeset | action: :validate}, as: :person))}
    end
  end

  # --- Metadata / save step ---

  def handle_event("save_relationship", params, socket) do
    person = socket.assigns.person
    selected = socket.assigns.selected_person
    type = socket.assigns.relationship_type

    result =
      case type do
        "parent" ->
          metadata_params = Map.get(params, "metadata", %{})

          Relationships.create_relationship(
            selected,
            person,
            "parent",
            atomize_metadata(metadata_params)
          )

        "partner" ->
          metadata_params = Map.get(params, "metadata", %{})

          Relationships.create_relationship(
            person,
            selected,
            "partner",
            atomize_metadata(metadata_params)
          )

        "child" ->
          role = if person.gender == "male", do: "father", else: "mother"

          case Relationships.create_relationship(person, selected, "parent", %{role: role}) do
            {:ok, _} = ok ->
              maybe_add_coparent(socket.assigns.partner_id, selected, person)
              ok

            error ->
              error
          end

        "child_solo" ->
          role = if person.gender == "male", do: "father", else: "mother"
          Relationships.create_relationship(person, selected, "parent", %{role: role})
      end

    case result do
      {:ok, _} ->
        send(self(), {:relationship_saved, type, selected})
        {:noreply, socket}

      {:error, reason} ->
        send(self(), {:relationship_error, relationship_error_message(reason)})
        {:noreply, socket}
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div id="add-relationship-component">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-xl font-bold text-base-content">
          {relationship_title(@relationship_type)}
        </h2>
        <button
          phx-click="cancel_add_relationship"
          class="p-2 rounded-lg text-base-content/30 hover:text-base-content hover:bg-base-200 transition-all"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <%= case @step do %>
        <% :search -> %>
          <div class="space-y-4">
            <p class="text-sm text-base-content/60">
              Search for an existing family member to add as a relationship.
            </p>
            <input
              id="relationship-search-input"
              type="text"
              placeholder="Type a name to search..."
              value={@search_query}
              phx-keyup="search_members"
              phx-target={@myself}
              phx-debounce="300"
              class="input input-bordered w-full"
              autocomplete="off"
            />

            <%= if @search_results != [] do %>
              <div class="space-y-1 max-h-60 overflow-y-auto">
                <%= for result <- @search_results do %>
                  <button
                    id={"search-result-#{result.id}"}
                    phx-click="select_person"
                    phx-target={@myself}
                    phx-value-id={result.id}
                    class="w-full text-left rounded-lg transition-colors hover:bg-base-200"
                  >
                    <.person_card_inline person={result} highlighted={false} />
                  </button>
                <% end %>
              </div>
            <% else %>
              <%= if String.length(@search_query) >= 2 do %>
                <p class="text-sm text-base-content/40 text-center py-4">
                  No results found
                </p>
              <% end %>
            <% end %>

            <button
              id="start-quick-create-btn"
              phx-click="start_quick_create"
              phx-target={@myself}
              class="flex items-center gap-1.5 text-sm text-primary/70 hover:text-primary w-full justify-center py-2 border-t border-base-200 mt-2 transition-colors"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Person not listed? Create new
            </button>
          </div>

        <% :quick_create -> %>
          <div id="quick-create-person">
            <button
              id="cancel-quick-create-btn"
              phx-click="cancel_quick_create"
              phx-target={@myself}
              class="flex items-center gap-1 text-sm text-primary/70 hover:text-primary mb-4 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to search
            </button>

            <p class="text-sm text-base-content/60 mb-4">
              Create a new person to add as a relationship.
            </p>

            <.form
              for={@person_form}
              id="quick-create-person-form"
              phx-target={@myself}
              phx-change="validate_person"
              phx-submit="save_person"
            >
              <div class="space-y-4">
                <.input field={@person_form[:given_name]} label="Given name" />
                <.input field={@person_form[:surname]} label="Surname" />
                <button type="submit" class="btn btn-primary w-full">
                  Create &amp; Continue
                </button>
              </div>
            </.form>
          </div>

        <% :metadata -> %>
          <div class="space-y-4">
            <div class="rounded-lg bg-base-200/50 p-3">
              <.person_card_inline person={@selected_person} highlighted={true} />
            </div>

            <%= cond do %>
              <% @relationship_type == "parent" && @relationship_form -> %>
                <.form
                  for={@relationship_form}
                  id="add-parent-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <div class="space-y-4">
                    <.input
                      field={@relationship_form[:role]}
                      type="select"
                      label="Role"
                      options={[{"Father", "father"}, {"Mother", "mother"}]}
                    />
                    <button type="submit" class="btn btn-primary w-full">Add Parent</button>
                  </div>
                </.form>

              <% @relationship_type == "partner" && @relationship_form -> %>
                <.form
                  for={@relationship_form}
                  id="add-partner-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <div class="space-y-4">
                    <p class="text-sm font-medium text-base-content/60">
                      Marriage Details (optional)
                    </p>
                    <div class="grid grid-cols-3 gap-3">
                      <.input
                        field={@relationship_form[:marriage_day]}
                        type="number"
                        placeholder="Day"
                        label="Day"
                      />
                      <.input
                        field={@relationship_form[:marriage_month]}
                        type="number"
                        placeholder="Month"
                        label="Month"
                      />
                      <.input
                        field={@relationship_form[:marriage_year]}
                        type="number"
                        placeholder="Year"
                        label="Year"
                      />
                    </div>
                    <.input
                      field={@relationship_form[:marriage_location]}
                      type="text"
                      label="Location"
                      placeholder="e.g. London, UK"
                    />
                    <button type="submit" class="btn btn-primary w-full">Add Partner</button>
                  </div>
                </.form>

              <% @relationship_type in ["child", "child_solo"] -> %>
                <.form
                  for={%{}}
                  as={:metadata}
                  id="add-child-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <button type="submit" class="btn btn-primary w-full">Add Child</button>
                </.form>

              <% true -> %>
                <p class="text-sm text-base-content/40">Unknown relationship type.</p>
            <% end %>

            <button
              phx-click="cancel_add_relationship"
              class="btn btn-ghost w-full"
            >
              Cancel
            </button>
          </div>
      <% end %>
    </div>
    """
  end

  # --- Private helpers ---

  defp person_card_inline(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 p-2 rounded-lg",
      @highlighted && "bg-primary/10 border border-primary/20"
    ]}>
      <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Ancestry.People.Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-medium text-sm text-base-content truncate">
          {Ancestry.People.Person.display_name(@person)}
        </p>
        <p class="text-xs text-base-content/50">
          <%= if @person.birth_year do %>
            {@person.birth_year}
          <% end %>
          <%= if @person.birth_year && @person.deceased do %>
            -
          <% end %>
          <%= if @person.deceased do %>
            <span title="This person is deceased.">
              {if @person.death_year, do: "d. #{@person.death_year}", else: "deceased"}
            </span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  defp build_relationship_form("parent", selected) do
    role = if selected.gender == "male", do: "father", else: "mother"
    to_form(%{"role" => role}, as: :metadata)
  end

  defp build_relationship_form("partner", _selected) do
    to_form(%{}, as: :metadata)
  end

  defp build_relationship_form(_type, _selected), do: nil

  defp maybe_add_coparent(nil, _child, _person), do: :ok

  defp maybe_add_coparent(partner_id, child, _person) do
    partner = People.get_person!(partner_id)
    partner_role = if partner.gender == "male", do: "father", else: "mother"

    case Relationships.create_relationship(partner, child, "parent", %{role: partner_role}) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp atomize_metadata(params) do
    Map.new(params, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k

      val =
        if is_binary(v) and v != "" and
             key in [
               :marriage_day,
               :marriage_month,
               :marriage_year,
               :divorce_day,
               :divorce_month,
               :divorce_year
             ] do
          case Integer.parse(v) do
            {int, ""} -> int
            _ -> v
          end
        else
          v
        end

      {key, val}
    end)
  end

  defp relationship_title("parent"), do: "Add Parent"
  defp relationship_title("partner"), do: "Add Partner"
  defp relationship_title("child"), do: "Add Child"
  defp relationship_title("child_solo"), do: "Add Child"
  defp relationship_title(_), do: "Add Relationship"

  defp relationship_error_message(:max_parents_reached), do: "This person already has 2 parents"
  defp relationship_error_message(%Ecto.Changeset{}), do: "Invalid relationship data"
  defp relationship_error_message(_), do: "Failed to create relationship"
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles successfully (no references yet from other modules)

**Step 3: Commit**

```bash
git add lib/web/live/shared/add_relationship_component.ex
git commit -m "Add shared AddRelationshipComponent for relationship creation"
```

---

### Task 2: Refactor `PersonLive.Show` to use the shared component

Replace the inline modal logic in `PersonLive.Show` with `AddRelationshipComponent`. Remove all relationship-adding event handlers and the `QuickCreateComponent` reference. Keep relationship editing/deleting/converting handlers (those stay in PersonLive.Show since they're not part of the tree view feature).

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`
- Delete: `lib/web/live/person_live/quick_create_component.ex`

**Step 1: Update `show.ex`**

Remove these event handlers from `show.ex` (lines 106-262):
- `handle_event("add_relationship", ...)`
- `handle_event("add_child_for_partner", ...)`
- `handle_event("cancel_add_relationship", ...)`
- `handle_event("start_quick_create", ...)`
- `handle_event("cancel_quick_create", ...)`
- `handle_event("search_members", ...)`
- `handle_event("select_person", ...)`
- `handle_event("save_relationship", ...)`

Remove `handle_info({:person_created, ...})` (lines 389-408).

Remove `atomize_metadata/1` and `relationship_error_message/1` private helpers (lines 487-520).

Replace them with these simpler handlers:

```elixir
# --- Relationship adding (delegated to shared component) ---

def handle_event("add_relationship", %{"type" => type}, socket) do
  {:noreply, assign(socket, :adding_relationship, type)}
end

def handle_event("add_child_for_partner", %{"partner-id" => partner_id}, socket) do
  {:noreply,
   socket
   |> assign(:adding_relationship, "child")
   |> assign(:adding_partner_id, String.to_integer(partner_id))}
end

def handle_event("cancel_add_relationship", _, socket) do
  {:noreply,
   socket
   |> assign(:adding_relationship, nil)
   |> assign(:adding_partner_id, nil)}
end
```

Replace `handle_info({:person_created, ...})` with:

```elixir
def handle_info({:relationship_saved, _type, _person}, socket) do
  {:noreply,
   socket
   |> load_relationships(socket.assigns.person)
   |> assign(:adding_relationship, nil)
   |> assign(:adding_partner_id, nil)
   |> put_flash(:info, "Relationship added")}
end

def handle_info({:relationship_error, message}, socket) do
  {:noreply, put_flash(socket, :error, message)}
end
```

In `load_relationships/2`, remove the assigns that are now handled by the component. Only reset `adding_relationship` and `adding_partner_id`:

Replace lines 474-484 (the tail of `load_relationships`) — keep only what the parent needs:

```elixir
    |> assign(:adding_relationship, nil)
    |> assign(:adding_partner_id, nil)
```

Remove these lines from `load_relationships` (the component manages its own state now):
- `:search_query`, `:search_results`, `:selected_person`, `:relationship_form`, `:quick_creating`

In `mount/3`, remove the assigns that the component now owns:
- `:search_query`, `:search_results`, `:selected_person`, `:relationship_form`, `:quick_creating`

Add `adding_partner_id` to mount if not already there. The `load_relationships` call already sets `adding_relationship` to nil so that's covered.

**Step 2: Update `show.html.heex`**

Replace the entire "Add Relationship Modal" block (lines 635-796) with:

```heex
<%!-- Add Relationship Modal --%>
<%= if @adding_relationship do %>
  <div class="fixed inset-0 z-50 flex items-center justify-center">
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="cancel_add_relationship"
    >
    </div>
    <div
      id="add-relationship-modal"
      class="relative card bg-base-100 shadow-2xl w-full max-w-lg mx-4 p-8 max-h-[90vh] overflow-y-auto"
    >
      <.live_component
        module={Web.Shared.AddRelationshipComponent}
        id="add-relationship"
        person={@person}
        family={@family}
        relationship_type={@adding_relationship}
        partner_id={@adding_partner_id}
      />
    </div>
  </div>
<% end %>
```

**Step 3: Delete `QuickCreateComponent`**

```bash
rm lib/web/live/person_live/quick_create_component.ex
```

**Step 4: Run existing tests to verify no regressions**

Run: `mix test test/web/live/person_live/relationships_test.exs test/web/live/person_live/quick_create_test.exs test/web/live/person_live/show_test.exs`

Expected: All tests pass. The DOM IDs used in tests (`#add-relationship-modal`, `#relationship-search-input`, `#search-result-*`, `#add-parent-form`, `#add-partner-form`, `#add-child-form`, `#quick-create-person-form`, `#quick-create-person`, `#start-quick-create-btn`, `#cancel-quick-create-btn`) are preserved in the shared component.

**Step 5: Commit**

```bash
git add -A
git commit -m "Refactor PersonLive.Show to use shared AddRelationshipComponent"
```

---

### Task 3: Rename `:spouse` to `:partner` in placeholder cards

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex`

**Step 1: Update the attr values, label, and all references**

In `person_card_component.ex`:

1. Line 71: Change `values: [:parent, :spouse, :child]` to `values: [:parent, :partner, :child]`
2. Line 101: Change `attr :show_spouse_placeholder` to `attr :show_partner_placeholder`
3. Line 161: Change `@show_spouse_placeholder` to `@show_partner_placeholder`
4. Line 168: Change `type={:spouse}` to `type={:partner}`
5. Line 222: Change `show_spouse_placeholder=` to `show_partner_placeholder=`
6. Line 392: Change `defp placeholder_label(:spouse), do: "Add Spouse"` to `defp placeholder_label(:partner), do: "Add Partner"`

**Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 3: Run existing tests**

Run: `mix test test/web/live/family_live/show_test.exs`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "Rename :spouse to :partner in placeholder cards"
```

---

### Task 4: Convert placeholder cards from links to buttons

Change placeholder cards from `<.link navigate=...>` to `<button phx-click="add_relationship">` so they fire events instead of navigating away.

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex`

**Step 1: Update `placeholder_card/1`**

Replace the current `placeholder_card` (lines 75-92) with:

```elixir
def placeholder_card(assigns) do
  ~H"""
  <button
    phx-click="add_relationship"
    phx-value-type={@type}
    phx-value-person-id={@person_id}
    class="flex flex-col items-center text-center w-28 rounded-lg p-2 border border-dashed border-base-content/20 hover:border-primary/50 hover:bg-primary/5 transition-all cursor-pointer group"
  >
    <div class="w-14 h-14 rounded-full bg-base-content/5 flex items-center justify-center mb-1 group-hover:bg-primary/10 transition-colors">
      <.icon
        name="hero-plus"
        class="w-6 h-6 text-base-content/30 group-hover:text-primary transition-colors"
      />
    </div>
    <p class="text-xs text-base-content/40 group-hover:text-primary transition-colors">
      {placeholder_label(@type)}
    </p>
  </button>
  """
end
```

Remove the `placeholder_link/3` helper functions (lines 395-401) — they are no longer needed.

Also remove the `:family_id` attr from `placeholder_card` since we no longer need it for URL generation.

**Step 2: Update all `placeholder_card` call sites to remove `family_id`**

In `family_subtree` (line 235):
```
<.placeholder_card type={:child} person_id={@unit.focus.id} family_id={@family_id} />
```
Change to:
```
<.placeholder_card type={:child} person_id={@unit.focus.id} />
```

In `couple_card` (lines 167-171):
```
<.placeholder_card type={:partner} person_id={@person_for_placeholder} family_id={@family_id} />
```
Change to:
```
<.placeholder_card type={:partner} person_id={@person_for_placeholder} />
```

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 4: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "Convert placeholder cards from navigation links to event buttons"
```

---

### Task 5: Add "Add Parent" placeholder to the tree view

Show an "Add Parent" placeholder above the focus person when they have fewer than 2 parents.

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex`
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Add parent count to tree data**

The tree `ancestors` field is `nil` when no parents exist, or contains `%{couple: %{person_a: _, person_b: _}, ...}`. We need to count parents to decide whether to show the placeholder. The simplest approach: count non-nil entries in the ancestor couple.

In `show.html.heex`, add the parent placeholder above the center row. Replace the ancestor + center section (lines 35-54):

```heex
<%= if @tree do %>
  <div class="inline-flex flex-col items-center gap-0 min-w-full">
    <%!-- Ancestor Tree (recursive: great-grandparents → parents) --%>
    <%= if @tree.ancestors do %>
      <.ancestor_subtree
        node={@tree.ancestors}
        family_id={@family.id}
        focused_person_id={@focus_person && @focus_person.id}
      />
      <.vline height={24} />
    <% end %>

    <%!-- Add Parent placeholder (when fewer than 2 parents) --%>
    <% parent_count = count_parents(@tree.ancestors) %>
    <%= if parent_count < 2 do %>
      <%= if parent_count == 0 do %>
        <.placeholder_card type={:parent} person_id={@focus_person.id} />
        <.vline height={16} />
      <% else %>
        <%!-- One parent exists, show placeholder next to them --%>
      <% end %>
    <% end %>

    <%!-- Center Row + Descendants (recursive) --%>
    <.family_subtree
      unit={@tree.center}
      family_id={@family.id}
      focused_person_id={@focus_person.id}
      is_root={true}
    />
  </div>
<% end %>
```

**Step 2: Add `count_parents/1` helper to `FamilyLive.Show`**

In `lib/web/live/family_live/show.ex`, add a private function:

```elixir
defp count_parents(nil), do: 0

defp count_parents(%{couple: %{person_a: a, person_b: b}}) do
  count = if a, do: 1, else: 0
  count + if(b, do: 1, else: 0)
end
```

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 4: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Add parent placeholder to tree view when fewer than 2 parents"
```

---

### Task 6: Wire `FamilyLive.Show` to the shared modal component

Add the `@adding_relationship` assign, event handlers, modal template, and `handle_info` callback to `FamilyLive.Show`.

**Files:**
- Modify: `lib/web/live/family_live/show.ex`
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Add assigns to `mount/3`**

In `show.ex` mount, add after the existing assigns:

```elixir
|> assign(:adding_relationship, nil)
```

**Step 2: Add event handlers**

Add to `show.ex`:

```elixir
# --- Add relationship from tree placeholders ---

def handle_event("add_relationship", %{"type" => type, "person-id" => person_id}, socket) do
  {:noreply,
   assign(socket, :adding_relationship, %{
     type: to_string(type),
     person_id: String.to_integer(person_id)
   })}
end

def handle_event("cancel_add_relationship", _, socket) do
  {:noreply, assign(socket, :adding_relationship, nil)}
end
```

**Step 3: Add `handle_info` callback**

```elixir
def handle_info({:relationship_saved, _type, _person}, socket) do
  family = socket.assigns.family
  people = People.list_people_for_family(family.id)
  focus_person = socket.assigns.focus_person

  # Reload focus person to get fresh data
  focus_person =
    if focus_person do
      Enum.find(people, &(&1.id == focus_person.id))
    end

  tree =
    if focus_person do
      PersonTree.build(focus_person)
    end

  {:noreply,
   socket
   |> assign(:people, people)
   |> assign(:focus_person, focus_person)
   |> assign(:tree, tree)
   |> assign(:adding_relationship, nil)
   |> put_flash(:info, "Relationship added")}
end

def handle_info({:relationship_error, message}, socket) do
  {:noreply, put_flash(socket, :error, message)}
end
```

**Step 4: Add modal template**

In `show.html.heex`, add before the `</Layouts.app>` closing tag (after the existing modals):

```heex
<%!-- Add Relationship Modal (from tree placeholders) --%>
<%= if @adding_relationship do %>
  <div class="fixed inset-0 z-50 flex items-center justify-center">
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="cancel_add_relationship"
    >
    </div>
    <div
      id="add-relationship-modal"
      class="relative card bg-base-100 shadow-2xl w-full max-w-lg mx-4 p-8 max-h-[90vh] overflow-y-auto"
    >
      <.live_component
        module={Web.Shared.AddRelationshipComponent}
        id="add-relationship"
        person={find_person(@people, @adding_relationship.person_id)}
        family={@family}
        relationship_type={@adding_relationship.type}
      />
    </div>
  </div>
<% end %>
```

**Step 5: Add `find_person/2` helper**

In `show.ex`:

```elixir
defp find_person(people, person_id) do
  Enum.find(people, &(&1.id == person_id)) || People.get_person!(person_id)
end
```

**Step 6: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 7: Run all tests**

Run: `mix test`
Expected: All pass

**Step 8: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Wire FamilyLive.Show to shared AddRelationshipComponent"
```

---

### Task 7: Write tests for tree view relationship adding

**Files:**
- Create: `test/web/live/family_live/tree_add_relationship_test.exs`

**Step 1: Write the test file**

```elixir
defmodule Web.FamilyLive.TreeAddRelationshipTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person}
  end

  describe "add partner from tree" do
    test "shows add partner placeholder when no partner", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='partner']")
    end

    test "hides partner placeholder when partner exists", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, spouse} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

      {:ok, _} = Relationships.create_relationship(person, spouse, "partner")

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "button[phx-value-type='partner']")
    end

    test "opens modal when clicking add partner placeholder", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "#add-relationship-modal")

      view |> element("button[phx-value-type='partner']") |> render_click()
      assert has_element?(view, "#add-relationship-modal")
      assert has_element?(view, "#relationship-search-input")
    end

    test "searches and adds a partner via modal", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Smith", gender: "female"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "Jan"})

      assert has_element?(view, "#search-result-#{candidate.id}")

      view |> element("#search-result-#{candidate.id}") |> render_click()
      assert has_element?(view, "#add-partner-form")

      view |> form("#add-partner-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      # Tree should now show partner
      html = render(view)
      assert html =~ "Jane"
    end

    test "quick creates a partner via modal", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      assert has_element?(view, "#quick-create-person-form")

      view
      |> form("#quick-create-person-form", person: %{given_name: "NewWife", surname: "Jones"})
      |> render_submit()

      assert has_element?(view, "#add-partner-form")

      view |> form("#add-partner-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "NewWife"
    end
  end

  describe "add child from tree" do
    test "shows add child placeholder when no children", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='child']")
    end

    test "opens modal and creates child", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='child']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      view
      |> form("#quick-create-person-form", person: %{given_name: "ChildName", surname: "Doe"})
      |> render_submit()

      assert has_element?(view, "#add-child-form")
      view |> form("#add-child-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
      html = render(view)
      assert html =~ "ChildName"
    end
  end

  describe "add parent from tree" do
    test "shows add parent placeholder when no parents", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      assert has_element?(view, "button[phx-value-type='parent']")
    end

    test "hides parent placeholder when 2 parents exist", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, father} =
        People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

      {:ok, mother} =
        People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

      {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, person, "parent", %{role: "mother"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")
      refute has_element?(view, "button[phx-value-type='parent']")
    end

    test "opens modal and adds parent", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='parent']") |> render_click()
      view |> element("#start-quick-create-btn") |> render_click()

      view
      |> form("#quick-create-person-form",
        person: %{given_name: "NewDad", surname: "Doe"}
      )
      |> render_submit()

      assert has_element?(view, "#add-parent-form")
      view |> form("#add-parent-form") |> render_submit()

      refute has_element?(view, "#add-relationship-modal")
    end
  end

  describe "modal behavior" do
    test "closes modal on backdrop click", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()
      assert has_element?(view, "#add-relationship-modal")

      render_click(view, "cancel_add_relationship")
      refute has_element?(view, "#add-relationship-modal")
    end

    test "keeps focus person after adding relationship", %{
      conn: conn,
      family: family,
      person: person
    } do
      {:ok, candidate} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{person.id}")

      view |> element("button[phx-value-type='partner']") |> render_click()

      view
      |> element("#relationship-search-input")
      |> render_keyup(%{value: "Jan"})

      view |> element("#search-result-#{candidate.id}") |> render_click()
      view |> form("#add-partner-form") |> render_submit()

      # Focus person should still be John
      assert has_element?(view, "#focus-person-card")
      html = render(view)
      assert html =~ "John"
    end
  end
end
```

**Step 2: Run the new tests**

Run: `mix test test/web/live/family_live/tree_add_relationship_test.exs`
Expected: All tests pass

**Step 3: Run the full test suite**

Run: `mix test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add test/web/live/family_live/tree_add_relationship_test.exs
git commit -m "Add tests for tree view relationship adding"
```

---

### Task 8: Run precommit and fix any issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (compile with warnings-as-errors, format, tests)

**Step 2: Fix any issues found**

If format or compile warnings appear, fix them and re-run.

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Fix precommit issues"
```
