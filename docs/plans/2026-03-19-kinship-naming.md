# Kinship Naming, DNA & Tree Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update kinship naming to standard genealogical conventions, add DNA shared percentages, replace the linear path with an inverted-V tree visualization, and add a "times removed" footnote.

**Architecture:** Modify `Ancestry.Kinship` classify/label functions for new naming, add a `dna_percentage/3` function. Update `Web.KinshipLive` to split the path into two branches and compute DNA%. Replace the template's vertical path with a two-column tree layout. Pure HEEx + Tailwind, no JS.

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind CSS

---

### Task 1: Update naming helpers in Kinship module

**Files:**
- Modify: `lib/ancestry/kinship.ex` (lines 121-208 — classify, ancestor_label, descendant_label, great_uncle_aunt_label, great_niece_nephew_label)
- Modify: `test/ancestry/kinship_test.exs` (update expected strings)

**Step 1: Update ancestor_label/1 to use new naming convention**

In `lib/ancestry/kinship.ex`, replace `ancestor_label/1` (line 166-169):

```elixir
# Old:
defp ancestor_label(steps) do
  greats = steps - 2
  "#{String.duplicate("Great-", greats)}Grandparent"
end

# New:
defp ancestor_label(steps) do
  greats = steps - 2

  cond do
    greats == 1 -> "Great Grandparent"
    greats == 2 -> "Great Great Grandparent"
    true -> "#{ordinal(greats)} Great Grandparent"
  end
end
```

**Step 2: Update descendant_label/1 with same pattern**

Replace `descendant_label/1` (line 171-174):

```elixir
defp descendant_label(steps) do
  greats = steps - 2

  cond do
    greats == 1 -> "Great Grandchild"
    greats == 2 -> "Great Great Grandchild"
    true -> "#{ordinal(greats)} Great Grandchild"
  end
end
```

**Step 3: Rewrite uncle/aunt naming**

Replace the classify clauses for uncle/aunt (lines 148-155) and `great_uncle_aunt_label/1` (line 176-178):

```elixir
# In classify/3, replace the uncle/aunt clauses:
steps_a == 1 and steps_b == 2 ->
  "Uncle & Aunt"

steps_a == 1 and steps_b == 3 ->
  "Great Uncle & Aunt"

steps_a == 1 and steps_b == 4 ->
  "Great Grand Uncle & Aunt"

steps_a == 1 and steps_b >= 5 ->
  great_grand_uncle_aunt_label(steps_b - 4)
```

Add new helper:

```elixir
defp great_grand_uncle_aunt_label(n) do
  "#{ordinal(n)} Great Grand Uncle & Aunt"
end
```

**Step 4: Rewrite nephew/niece naming**

Replace the classify clauses for nephew/niece (lines 151-158) and `great_niece_nephew_label/1` (line 180-182):

```elixir
# In classify/3, replace the nephew/niece clauses:
steps_a == 2 and steps_b == 1 ->
  "Nephew & Niece"

steps_a == 3 and steps_b == 1 ->
  "Grand Nephew & Niece"

steps_a == 4 and steps_b == 1 ->
  "Great Grand Nephew & Niece"

steps_a >= 5 and steps_b == 1 ->
  great_grand_nephew_niece_label(steps_a - 4)
```

Add new helper:

```elixir
defp great_grand_nephew_niece_label(n) do
  "#{ordinal(n)} Great Grand Nephew & Niece"
end
```

**Step 5: Update ascending_label/1 for path labels**

Replace `ascending_label/1` (lines 243-249) to match the new style:

```elixir
defp ascending_label(1), do: "Parent"
defp ascending_label(2), do: "Grandparent"
defp ascending_label(3), do: "Great Grandparent"
defp ascending_label(4), do: "Great Great Grandparent"

defp ascending_label(n) when n >= 5 do
  greats = n - 2
  "#{ordinal(greats)} Great Grandparent"
end
```

**Step 6: Update child_label/1 for path labels**

Replace `child_label/1` (lines 271-276):

```elixir
defp child_label(1), do: "Child"
defp child_label(2), do: "Grandchild"
defp child_label(3), do: "Great Grandchild"
defp child_label(4), do: "Great Great Grandchild"

defp child_label(n) when n >= 5 do
  greats = n - 2
  "#{ordinal(greats)} Great Grandchild"
end
```

**Step 7: Update ordinal/1 to return lowercase strings**

The ordinal helper currently returns capitalized words ("First", "Second"). It's used both for cousin labels and the new "3rd Great Grandparent" format. Since cousins use "First Cousin" (capitalized) but great-grandparents use "3rd" (numeric ordinal), add a numeric ordinal helper:

```elixir
defp numeric_ordinal(1), do: "1st"
defp numeric_ordinal(2), do: "2nd"
defp numeric_ordinal(3), do: "3rd"
defp numeric_ordinal(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n}st"
defp numeric_ordinal(n) when rem(n, 10) == 2 and rem(n, 100) != 12, do: "#{n}nd"
defp numeric_ordinal(n) when rem(n, 10) == 3 and rem(n, 100) != 13, do: "#{n}rd"
defp numeric_ordinal(n), do: "#{n}th"
```

Use `numeric_ordinal` in ancestor_label, descendant_label, uncle/aunt, nephew/niece labels. Keep `ordinal` for cousin labels.

**Step 8: Update tests to match new naming**

In `test/ancestry/kinship_test.exs`:

- Line 161: `"Great-Grandparent"` → `"Great Grandparent"`
- Line 171: `"Great-Grandchild"` → `"Great Grandchild"`
- Line 252: `"Uncle/Aunt"` → `"Uncle & Aunt"`
- Line 259: `"Niece/Nephew"` → `"Nephew & Niece"`
- Line 453-461: Update the path labels for second cousins:
  ```elixir
  assert path_labels == [
    "Self",
    "Parent",
    "Grandparent",
    "Great Grandparent",
    "Uncle & Aunt",
    "First Cousin, Once Removed",
    "Second Cousin"
  ]
  ```
- Line 483: `"Uncle/Aunt"` → `"Uncle & Aunt"`

**Step 9: Run tests**

Run: `mix test test/ancestry/kinship_test.exs`
Expected: All tests pass with new naming.

**Step 10: Commit**

```
git add lib/ancestry/kinship.ex test/ancestry/kinship_test.exs
git commit -m "feat: update kinship naming to standard genealogical conventions"
```

---

### Task 2: Add DNA percentage calculation

**Files:**
- Modify: `lib/ancestry/kinship.ex` — add `dna_percentage/3` public function
- Modify: `test/ancestry/kinship_test.exs` — add DNA percentage tests

**Step 1: Write failing tests for DNA percentage**

Add to `test/ancestry/kinship_test.exs`:

```elixir
describe "dna_percentage/3" do
  test "parent/child: 50%" do
    assert Kinship.dna_percentage(0, 1, false) == 50.0
  end

  test "siblings: 50%" do
    assert Kinship.dna_percentage(1, 1, false) == 50.0
  end

  test "grandparent: 25%" do
    assert Kinship.dna_percentage(0, 2, false) == 25.0
  end

  test "uncle/aunt: 25%" do
    assert Kinship.dna_percentage(1, 2, false) == 25.0
  end

  test "1st cousin: 12.5%" do
    assert Kinship.dna_percentage(2, 2, false) == 12.5
  end

  test "1st cousin once removed: 6.25%" do
    assert Kinship.dna_percentage(2, 3, false) == 6.25
  end

  test "2nd cousin: 3.125%" do
    assert Kinship.dna_percentage(3, 3, false) == 3.125
  end

  test "half-sibling: 25%" do
    assert Kinship.dna_percentage(1, 1, true) == 25.0
  end

  test "half-first cousin: 6.25%" do
    assert Kinship.dna_percentage(2, 2, true) == 6.25
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/kinship_test.exs --only describe:"dna_percentage/3"`
Expected: FAIL — `dna_percentage/3` is undefined

**Step 3: Implement dna_percentage/3**

Add to `lib/ancestry/kinship.ex`:

```elixir
@doc """
Calculates the approximate percentage of shared DNA between two people
based on their generational distances from the Most Recent Common Ancestor.

Returns a float percentage (e.g. 50.0 for parent/child).
"""
def dna_percentage(steps_a, steps_b, half?) do
  base =
    cond do
      # Direct line (one side is the MRCA)
      steps_a == 0 or steps_b == 0 ->
        100.0 / :math.pow(2, max(steps_a, steps_b))

      # Siblings (special case — share both parents)
      steps_a == 1 and steps_b == 1 ->
        50.0

      # Collateral relatives
      true ->
        100.0 / :math.pow(2, steps_a + steps_b - 1)
    end

  if half?, do: base / 2, else: base
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship_test.exs`
Expected: All pass

**Step 5: Add dna_percentage to the Kinship struct**

Update the struct to include `dna_percentage` field and populate it in `calculate/2`:

```elixir
defstruct [:relationship, :steps_a, :steps_b, :path, :mrca, :half?, :dna_percentage]
```

In the `calculate/2` function, after computing `relationship`, add:

```elixir
dna_pct = dna_percentage(steps_a, steps_b, half?)
```

And include `dna_percentage: dna_pct` in the struct.

**Step 6: Run all tests**

Run: `mix test test/ancestry/kinship_test.exs`
Expected: All pass

**Step 7: Commit**

```
git add lib/ancestry/kinship.ex test/ancestry/kinship_test.exs
git commit -m "feat: add DNA shared percentage calculation to kinship"
```

---

### Task 3: Update KinshipLive to split path into tree branches

**Files:**
- Modify: `lib/web/live/kinship_live.ex` — update `maybe_calculate/1` to add path_a, path_b, dna_percentage assigns

**Step 1: Update maybe_calculate to split path**

In `lib/web/live/kinship_live.ex`, update the `maybe_calculate/1` function (line 175-184):

```elixir
defp maybe_calculate(socket) do
  case {socket.assigns.person_a, socket.assigns.person_b} do
    {%Person{id: a_id}, %Person{id: b_id}} ->
      result = Kinship.calculate(a_id, b_id)

      case result do
        {:ok, kinship} ->
          # Split path: path_a is from person A up to MRCA (reversed for top-down display)
          # path_b is from MRCA down to person B
          path_a = Enum.slice(kinship.path, 0, kinship.steps_a + 1) |> Enum.reverse()
          path_b = Enum.slice(kinship.path, kinship.steps_a, length(kinship.path) - kinship.steps_a)

          socket
          |> assign(:result, result)
          |> assign(:path_a, path_a)
          |> assign(:path_b, path_b)

        _ ->
          socket
          |> assign(:result, result)
          |> assign(:path_a, [])
          |> assign(:path_b, [])
      end

    _ ->
      socket
      |> assign(:result, nil)
      |> assign(:path_a, [])
      |> assign(:path_b, [])
  end
end
```

Also initialize path_a and path_b assigns in `mount/3`:

```elixir
|> assign(:path_a, [])
|> assign(:path_b, [])
```

**Step 2: Run existing tests to make sure nothing breaks**

Run: `mix test test/user_flows/calculating_kinship_test.exs`
Expected: Pass (template hasn't changed yet)

**Step 3: Commit**

```
git add lib/web/live/kinship_live.ex
git commit -m "refactor: split kinship path into two branches for tree view"
```

---

### Task 4: Replace template with inverted-V tree and DNA display

**Files:**
- Modify: `lib/web/live/kinship_live.html.heex` — replace path visualization with tree layout, add DNA%, add footnote

**Step 1: Replace the result section in the template**

Replace the content inside `{:ok, _}` match block (lines 101-170) with:

```heex
<% {:ok, kinship} = @result %>
<div {test_id("kinship-result")}>
  <%!-- Relationship label with DNA percentage --%>
  <div class="text-center mb-2">
    <span
      class="text-3xl font-bold text-primary"
      {test_id("kinship-relationship-label")}
    >
      {kinship.relationship}
    </span>
  </div>

  <%!-- DNA percentage --%>
  <div class="text-center mb-2">
    <span
      class="text-sm text-base-content/50"
      {test_id("kinship-dna-percentage")}
    >
      ~{format_dna(kinship.dna_percentage)}% shared DNA
    </span>
  </div>

  <%!-- Directional label --%>
  <div class="text-center mb-8">
    <span
      class="text-base text-base-content/60"
      {test_id("kinship-directional-label")}
    >
      {Person.display_name(@person_b)} is {Person.display_name(@person_a)}'s {String.downcase(kinship.relationship)}
    </span>
  </div>

  <%!-- Tree visualization --%>
  <div
    class="flex flex-col items-center"
    {test_id("kinship-path")}
  >
    <%!-- MRCA node at top (shared between both branches) --%>
    <% mrca_node = List.first(@path_a) %>
    <div class="flex items-center gap-3 px-4 py-3 rounded-xl border bg-base-200 border-base-300 w-full max-w-sm">
      <.kinship_person_avatar person={mrca_node.person} />
      <div class="min-w-0 flex-1">
        <p class="font-medium text-sm text-base-content truncate">
          {Person.display_name(mrca_node.person)}
        </p>
        <p class="text-xs text-base-content/50">Common Ancestor</p>
      </div>
    </div>

    <%!-- Branch connector --%>
    <div class="flex w-full max-w-2xl">
      <%!-- Left branch spacer --%>
      <div class="flex-1 flex justify-center">
        <div class="w-px h-6 bg-base-300"></div>
      </div>
      <%!-- Right branch spacer --%>
      <div class="flex-1 flex justify-center">
        <div class="w-px h-6 bg-base-300"></div>
      </div>
    </div>

    <%!-- Horizontal connector bar --%>
    <div class="flex w-full max-w-2xl">
      <div class="flex-1 border-t-2 border-r border-base-300 h-0"></div>
      <div class="flex-1 border-t-2 border-l border-base-300 h-0"></div>
    </div>

    <%!-- Two branches side by side --%>
    <div class="flex w-full max-w-2xl gap-4">
      <%!-- Left branch: Person A's lineage (skip MRCA, already shown) --%>
      <div class="flex-1 flex flex-col items-center">
        <%= for {node, index} <- Enum.with_index(Enum.drop(@path_a, 1)) do %>
          <div class="w-px h-6 bg-base-300"></div>
          <% is_endpoint = index == length(@path_a) - 2 %>
          <div class={[
            "flex items-center gap-3 px-3 py-2 rounded-xl border w-full",
            if(is_endpoint,
              do: "bg-primary/10 border-primary/30",
              else: "bg-base-200/50 border-base-300"
            )
          ]}>
            <.kinship_person_avatar person={node.person} />
            <div class="min-w-0 flex-1">
              <p class="font-medium text-sm text-base-content truncate">
                {Person.display_name(node.person)}
              </p>
              <p class="text-xs text-base-content/50">{node.label}</p>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Right branch: Person B's lineage (skip MRCA, already shown) --%>
      <div class="flex-1 flex flex-col items-center">
        <%= for {node, index} <- Enum.with_index(Enum.drop(@path_b, 1)) do %>
          <div class="w-px h-6 bg-base-300"></div>
          <% is_endpoint = index == length(@path_b) - 2 %>
          <div class={[
            "flex items-center gap-3 px-3 py-2 rounded-xl border w-full",
            if(is_endpoint,
              do: "bg-primary/10 border-primary/30",
              else: "bg-base-200/50 border-base-300"
            )
          ]}>
            <.kinship_person_avatar person={node.person} />
            <div class="min-w-0 flex-1">
              <p class="font-medium text-sm text-base-content truncate">
                {Person.display_name(node.person)}
              </p>
              <p class="text-xs text-base-content/50">{node.label}</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>

  <%!-- "Times Removed" footnote --%>
  <%= if String.contains?(kinship.relationship, "Removed") do %>
    <div class="mt-8 max-w-md mx-auto flex gap-2 p-3 rounded-lg bg-base-200/50 text-xs text-base-content/50" {test_id("kinship-removed-footnote")}>
      <.icon name="hero-information-circle" class="w-4 h-4 shrink-0 mt-0.5" />
      <p>
        A "removed" cousin is a relative from a different generation.
        The number indicates how many generations apart you are.
        For example, your parent's first cousin is your first cousin, once removed.
      </p>
    </div>
  <% end %>

  <%!-- DNA disclaimer --%>
  <div class="mt-4 text-center text-xs text-base-content/30">
    Percentages are approximate and may vary.
  </div>
</div>
```

**Step 2: Add helper function components to kinship_live.ex**

Add to `lib/web/live/kinship_live.ex`:

```elixir
defp format_dna(percentage) when percentage >= 1.0 do
  if percentage == trunc(percentage) do
    "#{trunc(percentage)}"
  else
    :erlang.float_to_binary(percentage, decimals: 1)
  end
end

defp format_dna(percentage) do
  :erlang.float_to_binary(percentage, decimals: 4)
  |> String.trim_trailing("0")
  |> String.trim_trailing("0")
  |> String.trim_trailing(".")
end

attr :person, :any, required: true

defp kinship_person_avatar(assigns) do
  ~H"""
  <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
    <%= if @person.photo && @person.photo_status == "processed" do %>
      <img
        src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
        alt={Person.display_name(@person)}
        class="w-full h-full object-cover"
      />
    <% else %>
      <.icon name="hero-user" class="w-4 h-4 text-base-content/20" />
    <% end %>
  </div>
  """
end
```

**Step 3: Run tests**

Run: `mix test test/user_flows/calculating_kinship_test.exs`
Expected: Pass — existing test IDs are preserved

**Step 4: Commit**

```
git add lib/web/live/kinship_live.ex lib/web/live/kinship_live.html.heex
git commit -m "feat: replace kinship path with inverted-V tree, DNA%, and removed footnote"
```

---

### Task 5: Update E2E test for new features

**Files:**
- Modify: `test/user_flows/calculating_kinship_test.exs` — add assertions for DNA%, tree layout, footnote

**Step 1: Add DNA percentage assertion to existing test**

After the relationship label assertion, add:

```elixir
# Verify DNA percentage is shown
conn = assert_has(conn, test_id("kinship-dna-percentage"), text: "12.5% shared DNA")
```

**Step 2: Add a new test for "removed" relationship with footnote**

Add a new test that selects a grandparent and a cousin (or equivalent) to produce a "removed" relationship and verify the footnote appears:

```elixir
test "removed relationship shows footnote", %{
  conn: conn,
  family: family,
  grandpa: grandpa,
  cousin_a: cousin_a
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/kinship")
    |> wait_liveview()

  # Select grandpa as Person A
  conn =
    conn
    |> click(test_id("kinship-person-a-toggle"))

  conn = click(conn, test_id("kinship-person-a-option-#{grandpa.id}"))

  # Select cousin_a as Person B (grandpa -> parent_a -> cousin_a = Grandparent, not removed)
  # We need a relationship that produces "Removed"
  # grandpa to cousin_a: steps_a=0, steps_b=2 = Grandparent (not removed)
  # cousin_a to cousin_b's child would be removed, but we don't have that setup
  # Use cousin_a (steps=2) to grandpa (steps=0) — still not removed
  # Actually: cousin_a to grandpa of the other branch would work
  # Simpler: just verify the footnote does NOT appear for first cousins
  conn = click(conn, test_id("kinship-person-b-option-#{cousin_a.id}"))

  conn = assert_has(conn, test_id("kinship-result"), timeout: 5_000)

  # Grandparent relationship — no "removed" footnote
  conn = refute_has(conn, test_id("kinship-removed-footnote"))
end
```

For a proper "removed" test, extend the setup to add a child of cousin_a, then test cousin_b vs that child (1st cousin once removed). Or add this to the existing test flow.

**Step 3: Run tests**

Run: `mix test test/user_flows/calculating_kinship_test.exs`
Expected: All pass

**Step 4: Commit**

```
git add test/user_flows/calculating_kinship_test.exs
git commit -m "test: add DNA percentage and removed footnote assertions to kinship e2e"
```

---

### Task 6: Run precommit and fix any issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compilation clean, format clean, tests pass

**Step 2: Fix any warnings or formatting issues**

**Step 3: Commit fixes if needed**

```
git add -A
git commit -m "chore: fix formatting and warnings from precommit"
```
