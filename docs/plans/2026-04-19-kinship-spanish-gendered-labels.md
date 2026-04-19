# Gendered Direction-Aware Kinship Labels — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Ancestry.Kinship` produce gender-aware, direction-aware labels so Spanish translations use the correct forms (e.g., "Tío segundo" instead of "Primo/a Primero, una vez separado/a").

**Architecture:** Extract label formatting into a new `Ancestry.Kinship.Label` module that takes `(steps_a, steps_b, half?, gender)` and produces the correct label for the current locale. For non-removed relationships, use `pgettext(gender_context, msgid)` so each label gets male/female/other translations. For "removed" cousins (where English and Spanish have structurally different naming), build the labels programmatically per locale since the English "Nth Cousin, M Times Removed" is direction-agnostic but Spanish splits into Tío/Sobrino with different ordinals.

**Tech Stack:** Elixir Gettext (`pgettext`), Phoenix LiveView, existing `Ancestry.Kinship` module.

**Reference:** `GENEALOGY.md` at project root has the complete coordinate-to-label mapping.

---

### Task 1: Add `Ancestry.Kinship.Label` module with gendered direct-line labels

**Files:**
- Create: `lib/ancestry/kinship/label.ex`
- Create: `test/ancestry/kinship/label_test.exs`

- [ ] **Step 1: Write tests for direct-line labels (English locale)**

```elixir
# test/ancestry/kinship/label_test.exs
defmodule Ancestry.Kinship.LabelTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.Label

  describe "format/4 - direct line ascending" do
    test "parent" do
      assert Label.format(0, 1, false, "male") == "Parent"
      assert Label.format(0, 1, false, "female") == "Parent"
      assert Label.format(0, 1, false, "other") == "Parent"
      assert Label.format(0, 1, false, nil) == "Parent"
    end

    test "grandparent" do
      assert Label.format(0, 2, false, "male") == "Grandparent"
    end

    test "great grandparent" do
      assert Label.format(0, 3, false, "male") == "Great Grandparent"
    end

    test "great great grandparent" do
      assert Label.format(0, 4, false, "male") == "Great Great Grandparent"
    end

    test "3rd great grandparent" do
      assert Label.format(0, 5, false, "male") == "3rd Great Grandparent"
    end

    test "4th great grandparent" do
      assert Label.format(0, 6, false, "male") == "4th Great Grandparent"
    end

    test "7th great grandparent" do
      assert Label.format(0, 9, false, "male") == "7th Great Grandparent"
    end
  end

  describe "format/4 - direct line descending" do
    test "child" do
      assert Label.format(1, 0, false, "male") == "Child"
    end

    test "grandchild" do
      assert Label.format(2, 0, false, "male") == "Grandchild"
    end

    test "great grandchild" do
      assert Label.format(3, 0, false, "male") == "Great Grandchild"
    end

    test "great great grandchild" do
      assert Label.format(4, 0, false, "male") == "Great Great Grandchild"
    end

    test "3rd great grandchild" do
      assert Label.format(5, 0, false, "male") == "3rd Great Grandchild"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`
Expected: compilation errors — `Ancestry.Kinship.Label` module not found.

- [ ] **Step 3: Implement `Label.format/4` for direct-line cases**

```elixir
# lib/ancestry/kinship/label.ex
defmodule Ancestry.Kinship.Label do
  @moduledoc """
  Produces human-readable kinship labels based on the coordinate system
  (steps_a, steps_b), half-relationship flag, and the person's gender.

  The label describes what person A is to person B.
  Gender refers to person A's gender.

  See GENEALOGY.md for the complete coordinate-to-label mapping.
  """

  use Gettext, backend: Web.Gettext

  @doc """
  Formats a kinship label for the given coordinates and gender.

  ## Parameters
    - `steps_a` - Person A's distance to MRCA
    - `steps_b` - Person B's distance to MRCA
    - `half?` - Whether this is a half-relationship
    - `gender` - Person A's gender ("male", "female", "other", or nil)
  """
  def format(steps_a, steps_b, half?, gender) do
    g = normalize_gender(gender)
    classify(steps_a, steps_b, half?, g)
  end

  defp normalize_gender("male"), do: "male"
  defp normalize_gender("female"), do: "female"
  defp normalize_gender(_), do: "other"

  # --- Direct line ascending (A is B's ancestor) ---

  defp classify(0, 1, _half?, g), do: pgettext(g, "Parent")
  defp classify(0, 2, _half?, g), do: pgettext(g, "Grandparent")
  defp classify(0, steps_b, _half?, g) when steps_b >= 3, do: ancestor_label(steps_b, g)

  # --- Direct line descending (A is B's descendant) ---

  defp classify(1, 0, _half?, g), do: pgettext(g, "Child")
  defp classify(2, 0, _half?, g), do: pgettext(g, "Grandchild")
  defp classify(steps_a, 0, _half?, g) when steps_a >= 3, do: descendant_label(steps_a, g)

  # --- Placeholder for remaining cases (will be filled in subsequent tasks) ---

  defp classify(steps_a, steps_b, half?, g) do
    # Temporary: delegate to old logic format for cases not yet migrated
    Ancestry.Kinship.classify_legacy(steps_a, steps_b, half?)
  end

  # --- Ancestor labels ---

  defp ancestor_label(steps, g) do
    greats = steps - 2

    cond do
      greats == 1 -> pgettext(g, "Great Grandparent")
      greats == 2 -> pgettext(g, "Great Great Grandparent")
      greats >= 3 -> pgettext(g, "%{nth} Great Grandparent", nth: numeric_ordinal(greats))
    end
  end

  # --- Descendant labels ---

  defp descendant_label(steps, g) do
    greats = steps - 2

    cond do
      greats == 1 -> pgettext(g, "Great Grandchild")
      greats == 2 -> pgettext(g, "Great Great Grandchild")
      greats >= 3 -> pgettext(g, "%{nth} Great Grandchild", nth: numeric_ordinal(greats))
    end
  end

  # --- Numeric ordinals (language-independent) ---

  defp numeric_ordinal(1), do: "1st"
  defp numeric_ordinal(2), do: "2nd"
  defp numeric_ordinal(3), do: "3rd"
  defp numeric_ordinal(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n}st"
  defp numeric_ordinal(n) when rem(n, 10) == 2 and rem(n, 100) != 12, do: "#{n}nd"
  defp numeric_ordinal(n) when rem(n, 10) == 3 and rem(n, 100) != 13, do: "#{n}rd"
  defp numeric_ordinal(n), do: "#{n}th"
end
```

Note: The `classify_legacy/3` function will be temporarily exposed in `Ancestry.Kinship` (next task handles wiring). For now, just get the module compiling and direct-line tests passing.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`
Expected: All direct-line tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/label.ex test/ancestry/kinship/label_test.exs
git commit -m "Add Kinship.Label module with gendered direct-line labels"
```

---

### Task 2: Add sibling and first-collateral-line labels (uncle/aunt, nephew/niece)

**Files:**
- Modify: `lib/ancestry/kinship/label.ex`
- Modify: `test/ancestry/kinship/label_test.exs`

- [ ] **Step 1: Write tests for siblings and uncle/nephew chain**

```elixir
# Add to label_test.exs

describe "format/4 - siblings" do
  test "sibling" do
    assert Label.format(1, 1, false, "male") == "Sibling"
  end

  test "half-sibling" do
    assert Label.format(1, 1, true, "male") == "Half-Sibling"
  end
end

describe "format/4 - uncle/aunt chain (steps_a=1)" do
  test "uncle/aunt" do
    assert Label.format(1, 2, false, "male") == "Uncle & Aunt"
  end

  test "great uncle/aunt" do
    assert Label.format(1, 3, false, "male") == "Great Uncle & Aunt"
  end

  test "great grand uncle/aunt" do
    assert Label.format(1, 4, false, "male") == "Great Grand Uncle & Aunt"
  end

  test "nth great grand uncle/aunt" do
    assert Label.format(1, 5, false, "male") == "1st Great Grand Uncle & Aunt"
    assert Label.format(1, 6, false, "male") == "2nd Great Grand Uncle & Aunt"
  end
end

describe "format/4 - nephew/niece chain (steps_b=1)" do
  test "nephew/niece" do
    assert Label.format(2, 1, false, "male") == "Nephew & Niece"
  end

  test "grand nephew/niece" do
    assert Label.format(3, 1, false, "male") == "Grand Nephew & Niece"
  end

  test "great grand nephew/niece" do
    assert Label.format(4, 1, false, "male") == "Great Grand Nephew & Niece"
  end

  test "nth great grand nephew/niece" do
    assert Label.format(5, 1, false, "male") == "1st Great Grand Nephew & Niece"
    assert Label.format(6, 1, false, "male") == "2nd Great Grand Nephew & Niece"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`

- [ ] **Step 3: Add sibling and uncle/nephew clauses to `Label.classify/4`**

Add these clauses between the direct-line and the placeholder catch-all in `label.ex`:

```elixir
# --- Siblings ---
defp classify(1, 1, true, g), do: pgettext(g, "Half-Sibling")
defp classify(1, 1, false, g), do: pgettext(g, "Sibling")

# --- Uncle/Aunt chain (first collateral ascending, steps_a=1) ---
defp classify(1, 2, _half?, g), do: pgettext(g, "Uncle & Aunt")
defp classify(1, 3, _half?, g), do: pgettext(g, "Great Uncle & Aunt")
defp classify(1, 4, _half?, g), do: pgettext(g, "Great Grand Uncle & Aunt")

defp classify(1, steps_b, _half?, g) when steps_b >= 5 do
  pgettext(g, "%{nth} Great Grand Uncle & Aunt", nth: numeric_ordinal(steps_b - 4))
end

# --- Nephew/Niece chain (first collateral descending, steps_b=1) ---
defp classify(2, 1, _half?, g), do: pgettext(g, "Nephew & Niece")
defp classify(3, 1, _half?, g), do: pgettext(g, "Grand Nephew & Niece")
defp classify(4, 1, _half?, g), do: pgettext(g, "Great Grand Nephew & Niece")

defp classify(steps_a, 1, _half?, g) when steps_a >= 5 do
  pgettext(g, "%{nth} Great Grand Nephew & Niece", nth: numeric_ordinal(steps_a - 4))
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/label.ex test/ancestry/kinship/label_test.exs
git commit -m "Add sibling, uncle/aunt, nephew/niece labels to Kinship.Label"
```

---

### Task 3: Add same-generation cousin labels and removed cousin labels

This is the core task. For same-generation cousins, use `pgettext` with gendered ordinals. For removed cousins, build labels programmatically per locale since English (direction-agnostic "Nth Cousin, M Times Removed") and Spanish (direction-aware Tío/Sobrino) have structurally different naming.

**Files:**
- Modify: `lib/ancestry/kinship/label.ex`
- Modify: `test/ancestry/kinship/label_test.exs`

- [ ] **Step 1: Write tests for same-generation cousins and removed cousins**

```elixir
# Add to label_test.exs

describe "format/4 - same-generation cousins (removed=0)" do
  test "first cousin" do
    assert Label.format(2, 2, false, "male") == "First Cousin"
  end

  test "second cousin" do
    assert Label.format(3, 3, false, "male") == "Second Cousin"
  end

  test "third cousin" do
    assert Label.format(4, 4, false, "male") == "Third Cousin"
  end

  test "half first cousin" do
    assert Label.format(2, 2, true, "male") == "Half-First Cousin"
  end

  test "half second cousin" do
    assert Label.format(3, 3, true, "male") == "Half-Second Cousin"
  end
end

describe "format/4 - removed cousins (English, direction-agnostic)" do
  test "first cousin once removed - ascending" do
    assert Label.format(2, 3, false, "male") == "First Cousin, Once Removed"
  end

  test "first cousin once removed - descending" do
    assert Label.format(3, 2, false, "male") == "First Cousin, Once Removed"
  end

  test "second cousin once removed" do
    assert Label.format(3, 4, false, "male") == "Second Cousin, Once Removed"
  end

  test "first cousin twice removed" do
    assert Label.format(2, 4, false, "male") == "First Cousin, Twice Removed"
  end

  test "first cousin 3 times removed" do
    assert Label.format(2, 5, false, "male") == "First Cousin, 3 Times Removed"
  end

  test "half first cousin once removed" do
    assert Label.format(2, 3, true, "male") == "Half-First Cousin, Once Removed"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`

- [ ] **Step 3: Implement cousin labels in `Label`**

Replace the placeholder catch-all `classify/4` clause with the full cousin logic:

```elixir
# --- Cousins (both steps >= 2) ---

defp classify(steps_a, steps_b, half?, g) do
  half_prefix = if(half?, do: pgettext(g, "Half-"), else: "")
  "#{half_prefix}#{cousin_or_removed_label(steps_a, steps_b, g)}"
end

# Same-generation cousin
defp cousin_or_removed_label(steps_a, steps_b, g) when steps_a == steps_b do
  degree = steps_a - 1
  degree_str = ordinal(degree, g)
  pgettext(g, "%{degree} Cousin", degree: degree_str)
end

# Removed cousin — build per locale
defp cousin_or_removed_label(steps_a, steps_b, g) do
  locale = Gettext.get_locale(Web.Gettext)

  case locale do
    "es" <> _ -> spanish_removed_label(steps_a, steps_b, g)
    _ -> english_removed_label(steps_a, steps_b, g)
  end
end

# --- English removed cousin (direction-agnostic) ---

defp english_removed_label(steps_a, steps_b, g) do
  degree = min(steps_a, steps_b) - 1
  removed = abs(steps_a - steps_b)
  degree_str = ordinal(degree, g)

  removed_str =
    cond do
      removed == 1 -> pgettext(g, ", Once Removed")
      removed == 2 -> pgettext(g, ", Twice Removed")
      true -> pgettext(g, ", %{count} Times Removed", count: removed)
    end

  pgettext(g, "%{degree} Cousin%{removed}", degree: degree_str, removed: removed_str)
end

# --- Spanish removed cousin (direction-aware: Tío/Sobrino) ---

defp spanish_removed_label(steps_a, steps_b, g) do
  ordinal_n = min(steps_a, steps_b)
  removed = abs(steps_a - steps_b)
  direction = if steps_a < steps_b, do: :ascending, else: :descending

  base = spanish_base(direction, g)
  gen_suffix = spanish_generation_suffix(removed, direction, g)
  ord_suffix = spanish_ordinal_suffix(ordinal_n, g)

  [base, gen_suffix, ord_suffix]
  |> Enum.reject(&(&1 == ""))
  |> Enum.join(" ")
end

defp spanish_base(:ascending, "male"), do: "Tío"
defp spanish_base(:ascending, "female"), do: "Tía"
defp spanish_base(:ascending, _), do: "Tío/a"
defp spanish_base(:descending, "male"), do: "Sobrino"
defp spanish_base(:descending, "female"), do: "Sobrina"
defp spanish_base(:descending, _), do: "Sobrino/a"

defp spanish_generation_suffix(1, _direction, _g), do: ""

defp spanish_generation_suffix(removed, :ascending, g) do
  spanish_ancestor_suffix(removed, g)
end

defp spanish_generation_suffix(removed, :descending, g) do
  spanish_descendant_suffix(removed, g)
end

defp spanish_ancestor_suffix(2, "male"), do: "abuelo"
defp spanish_ancestor_suffix(2, "female"), do: "abuela"
defp spanish_ancestor_suffix(2, _), do: "abuelo/a"
defp spanish_ancestor_suffix(3, "male"), do: "bisabuelo"
defp spanish_ancestor_suffix(3, "female"), do: "bisabuela"
defp spanish_ancestor_suffix(3, _), do: "bisabuelo/a"
defp spanish_ancestor_suffix(4, "male"), do: "tatarabuelo"
defp spanish_ancestor_suffix(4, "female"), do: "tatarabuela"
defp spanish_ancestor_suffix(4, _), do: "tatarabuelo/a"
defp spanish_ancestor_suffix(5, "male"), do: "trastatarabuelo"
defp spanish_ancestor_suffix(5, "female"), do: "trastatarabuela"
defp spanish_ancestor_suffix(5, _), do: "trastatarabuelo/a"

defp spanish_ancestor_suffix(n, "male"), do: "#{n}° abuelo"
defp spanish_ancestor_suffix(n, "female"), do: "#{n}° abuela"
defp spanish_ancestor_suffix(n, _), do: "#{n}° abuelo/a"

defp spanish_descendant_suffix(2, "male"), do: "nieto"
defp spanish_descendant_suffix(2, "female"), do: "nieta"
defp spanish_descendant_suffix(2, _), do: "nieto/a"
defp spanish_descendant_suffix(3, "male"), do: "bisnieto"
defp spanish_descendant_suffix(3, "female"), do: "bisnieta"
defp spanish_descendant_suffix(3, _), do: "bisnieto/a"
defp spanish_descendant_suffix(4, "male"), do: "tataranieto"
defp spanish_descendant_suffix(4, "female"), do: "tataranieta"
defp spanish_descendant_suffix(4, _), do: "tataranieto/a"
defp spanish_descendant_suffix(5, "male"), do: "trastataranieto"
defp spanish_descendant_suffix(5, "female"), do: "trastataranieta"
defp spanish_descendant_suffix(5, _), do: "trastataranieto/a"

defp spanish_descendant_suffix(n, "male"), do: "#{n}° nieto"
defp spanish_descendant_suffix(n, "female"), do: "#{n}° nieta"
defp spanish_descendant_suffix(n, _), do: "#{n}° nieto/a"

defp spanish_ordinal_suffix(1, _g), do: ""

defp spanish_ordinal_suffix(n, g) do
  spanish_ordinal(n, g)
end

defp spanish_ordinal(2, "male"), do: "segundo"
defp spanish_ordinal(2, "female"), do: "segunda"
defp spanish_ordinal(2, _), do: "segundo/a"
defp spanish_ordinal(3, "male"), do: "tercero"
defp spanish_ordinal(3, "female"), do: "tercera"
defp spanish_ordinal(3, _), do: "tercero/a"
defp spanish_ordinal(4, "male"), do: "cuarto"
defp spanish_ordinal(4, "female"), do: "cuarta"
defp spanish_ordinal(4, _), do: "cuarto/a"
defp spanish_ordinal(5, "male"), do: "quinto"
defp spanish_ordinal(5, "female"), do: "quinta"
defp spanish_ordinal(5, _), do: "quinto/a"
defp spanish_ordinal(6, "male"), do: "sexto"
defp spanish_ordinal(6, "female"), do: "sexta"
defp spanish_ordinal(6, _), do: "sexto/a"
defp spanish_ordinal(7, "male"), do: "séptimo"
defp spanish_ordinal(7, "female"), do: "séptima"
defp spanish_ordinal(7, _), do: "séptimo/a"
defp spanish_ordinal(8, "male"), do: "octavo"
defp spanish_ordinal(8, "female"), do: "octava"
defp spanish_ordinal(8, _), do: "octavo/a"
defp spanish_ordinal(n, _), do: "#{n}°"

# --- English ordinals (used for cousin degree) ---

defp ordinal(1, g), do: pgettext(g, "First")
defp ordinal(2, g), do: pgettext(g, "Second")
defp ordinal(3, g), do: pgettext(g, "Third")
defp ordinal(4, g), do: pgettext(g, "Fourth")
defp ordinal(5, g), do: pgettext(g, "Fifth")
defp ordinal(6, g), do: pgettext(g, "Sixth")
defp ordinal(7, g), do: pgettext(g, "Seventh")
defp ordinal(8, g), do: pgettext(g, "Eighth")
defp ordinal(n, _g), do: "#{n}th"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/label.ex test/ancestry/kinship/label_test.exs
git commit -m "Add cousin and direction-aware removed cousin labels"
```

---

### Task 4: Add Spanish locale tests for `Label`

**Files:**
- Modify: `test/ancestry/kinship/label_test.exs`

- [ ] **Step 1: Write Spanish locale tests**

```elixir
# Add to label_test.exs

describe "format/4 - Spanish locale" do
  setup do
    Gettext.put_locale(Web.Gettext, "es-UY")
    on_exit(fn -> Gettext.put_locale(Web.Gettext, "en-US") end)
  end

  test "parent gendered" do
    assert Label.format(0, 1, false, "male") == "Padre"
    assert Label.format(0, 1, false, "female") == "Madre"
    assert Label.format(0, 1, false, "other") == "Padre/Madre"
  end

  test "grandparent gendered" do
    assert Label.format(0, 2, false, "male") == "Abuelo"
    assert Label.format(0, 2, false, "female") == "Abuela"
  end

  test "bisabuelo/a" do
    assert Label.format(0, 3, false, "male") == "Bisabuelo"
    assert Label.format(0, 3, false, "female") == "Bisabuela"
  end

  test "tatarabuelo/a" do
    assert Label.format(0, 4, false, "male") == "Tatarabuelo"
    assert Label.format(0, 4, false, "female") == "Tatarabuela"
  end

  test "trastatarabuelo/a" do
    assert Label.format(0, 5, false, "male") == "Trastatarabuelo"
    assert Label.format(0, 5, false, "female") == "Trastatarabuela"
  end

  test "numeric ordinal ancestors" do
    assert Label.format(0, 6, false, "male") == "5° Abuelo"
    assert Label.format(0, 6, false, "female") == "5° Abuela"
  end

  test "child gendered" do
    assert Label.format(1, 0, false, "male") == "Hijo"
    assert Label.format(1, 0, false, "female") == "Hija"
  end

  test "sibling gendered" do
    assert Label.format(1, 1, false, "male") == "Hermano"
    assert Label.format(1, 1, false, "female") == "Hermana"
  end

  test "half-sibling gendered" do
    assert Label.format(1, 1, true, "male") == "Medio hermano"
    assert Label.format(1, 1, true, "female") == "Media hermana"
  end

  test "uncle/aunt gendered" do
    assert Label.format(1, 2, false, "male") == "Tío"
    assert Label.format(1, 2, false, "female") == "Tía"
  end

  test "nephew/niece gendered" do
    assert Label.format(2, 1, false, "male") == "Sobrino"
    assert Label.format(2, 1, false, "female") == "Sobrina"
  end

  test "great uncle gendered" do
    assert Label.format(1, 3, false, "male") == "Tío abuelo"
    assert Label.format(1, 3, false, "female") == "Tía abuela"
  end

  test "grand nephew gendered" do
    assert Label.format(3, 1, false, "male") == "Sobrino nieto"
    assert Label.format(3, 1, false, "female") == "Sobrina nieta"
  end

  test "first cousin gendered" do
    assert Label.format(2, 2, false, "male") == "Primo"
    assert Label.format(2, 2, false, "female") == "Prima"
  end

  test "second cousin gendered" do
    assert Label.format(3, 3, false, "male") == "Primo segundo"
    assert Label.format(3, 3, false, "female") == "Prima segunda"
  end

  test "removed cousin ascending - tío segundo" do
    assert Label.format(2, 3, false, "male") == "Tío segundo"
    assert Label.format(2, 3, false, "female") == "Tía segunda"
  end

  test "removed cousin descending - sobrino segundo" do
    assert Label.format(3, 2, false, "male") == "Sobrino segundo"
    assert Label.format(3, 2, false, "female") == "Sobrina segunda"
  end

  test "removed=2 ascending - tío abuelo segundo" do
    assert Label.format(2, 4, false, "male") == "Tío abuelo segundo"
    assert Label.format(2, 4, false, "female") == "Tía abuela segunda"
  end

  test "removed=2 descending - sobrino nieto segundo" do
    assert Label.format(4, 2, false, "male") == "Sobrino nieto segundo"
    assert Label.format(4, 2, false, "female") == "Sobrina nieta segunda"
  end

  test "removed cousin higher ordinal" do
    assert Label.format(3, 4, false, "male") == "Tío tercero"
    assert Label.format(4, 3, false, "female") == "Sobrina tercera"
  end

  test "half cousin" do
    assert Label.format(2, 2, true, "male") == "Medio primo"
    assert Label.format(2, 2, true, "female") == "Media prima"
  end

  test "half removed cousin" do
    assert Label.format(2, 3, true, "male") == "Medio tío segundo"
    assert Label.format(2, 3, true, "female") == "Media tía segunda"
  end
end
```

- [ ] **Step 2: Run tests — they will fail because .po translations don't exist yet**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`
Expected: FAIL — pgettext returns untranslated msgids for Spanish.

- [ ] **Step 3: Add pgettext translations to .po files**

This requires adding `msgctxt` entries to both `priv/gettext/es-UY/LC_MESSAGES/default.po` and `priv/gettext/en-US/LC_MESSAGES/default.po`. Do NOT run `mix gettext.extract` yet — add the entries manually.

**For `es-UY/default.po`**, add entries like:

```po
msgctxt "male"
msgid "Parent"
msgstr "Padre"

msgctxt "female"
msgid "Parent"
msgstr "Madre"

msgctxt "other"
msgid "Parent"
msgstr "Padre/Madre"

msgctxt "male"
msgid "Grandparent"
msgstr "Abuelo"

msgctxt "female"
msgid "Grandparent"
msgstr "Abuela"

msgctxt "other"
msgid "Grandparent"
msgstr "Abuelo/a"
```

Continue this pattern for ALL labels: Parent, Grandparent, Great Grandparent, Great Great Grandparent, "%{nth} Great Grandparent", Child, Grandchild, Great Grandchild, Great Great Grandchild, "%{nth} Great Grandchild", Sibling, Half-Sibling, "Uncle & Aunt", "Great Uncle & Aunt", "Great Grand Uncle & Aunt", "%{nth} Great Grand Uncle & Aunt", "Nephew & Niece", "Grand Nephew & Niece", "Great Grand Nephew & Niece", "%{nth} Great Grand Nephew & Niece", "Half-", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "%{degree} Cousin", "%{degree} Cousin%{removed}", ", Once Removed", ", Twice Removed", ", %{count} Times Removed".

**For `en-US/default.po`**, add gendered entries for labels that change in English too:

```po
msgctxt "male"
msgid "Uncle & Aunt"
msgstr "Uncle"

msgctxt "female"
msgid "Uncle & Aunt"
msgstr "Aunt"

msgctxt "male"
msgid "Nephew & Niece"
msgstr "Nephew"

msgctxt "female"
msgid "Nephew & Niece"
msgstr "Niece"

msgctxt "male"
msgid "Great Uncle & Aunt"
msgstr "Great Uncle"

msgctxt "female"
msgid "Great Uncle & Aunt"
msgstr "Great Aunt"
```

And similar entries for all gendered English labels.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/label_test.exs --trace`

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/label.ex test/ancestry/kinship/label_test.exs priv/gettext/
git commit -m "Add Spanish gendered translations for all kinship labels"
```

---

### Task 5: Wire `Label.format` into `Kinship.calculate/2` and path labels

Replace the old `classify/3` usage in `Kinship` with `Label.format/4`, passing each person's gender.

**Files:**
- Modify: `lib/ancestry/kinship.ex`

- [ ] **Step 1: Update `calculate/2` to pass person A's gender to `Label.format`**

In `lib/ancestry/kinship.ex`, change the `calculate/2` function:

```elixir
# Replace:
relationship = classify(steps_a, steps_b, half?)
path = build_path(path_a, path_b, steps_a, steps_b)

# With:
person_a = People.get_person!(person_a_id)
relationship = Label.format(steps_a, steps_b, half?, person_a.gender)
path = build_path(path_a, path_b, steps_a, steps_b)
```

Add `alias Ancestry.Kinship.Label` at the top of the module.

- [ ] **Step 2: Update `build_path` to pass each person's gender to path labels**

```elixir
# Replace the build_path inner map function:
|> Enum.map(fn {id, index} ->
  person = People.get_person!(id)
  label = path_label(index, steps_a, steps_b)
  %{person: person, label: label}
end)

# With:
|> Enum.map(fn {id, index} ->
  person = People.get_person!(id)
  label = path_label(index, steps_a, steps_b, person.gender)
  %{person: person, label: label}
end)
```

- [ ] **Step 3: Update `path_label` to use `Label.format` with gender**

```elixir
defp path_label(0, _steps_a, _steps_b, _gender), do: "Self"

defp path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
  Label.format(0, index, false, gender)
end

defp path_label(index, steps_a, _steps_b, gender) do
  down_steps = index - steps_a

  cond do
    steps_a == 0 ->
      Label.format(down_steps, 0, false, gender)

    true ->
      Label.format(down_steps, steps_a, false, gender)
  end
end
```

- [ ] **Step 4: Remove old `classify/3` and its helpers from `Kinship`**

Delete these private functions from `kinship.ex` (they are now in `Label`):
- `classify/3`
- `ancestor_label/1`
- `descendant_label/1`
- `cousin_label/2`
- `ordinal/1`
- `numeric_ordinal/1`
- `ascending_label/1`
- `descending_label/3`
- `child_label/1`

Keep: `dna_percentage/3`, `calculate/2`, `build_ancestor_map/1`, `bfs_expand/3`, `half_relationship?/5`, `build_path/4`, `path_label/4`.

- [ ] **Step 5: Run existing kinship tests**

Run: `mix test test/ancestry/kinship_test.exs --trace`

Many tests will fail because they assert exact string matches like `"Parent"`, `"Uncle & Aunt"`, `"First Cousin, Once Removed"`. These are still correct for English locale — the pgettext fallback returns the msgid when no translation exists. Check which tests fail and fix only assertions that changed semantically.

The path label tests may need updating — for example, the test for second cousin path expects `"First Cousin, Once Removed"` as an intermediate label. This should still work in English locale since `Label.format` falls back to the old English labels.

- [ ] **Step 6: Fix any failing tests**

Review each failure. The most likely issue is that `path_label` now calls `Label.format(0, index, ...)` instead of `ascending_label(index)` — verify these produce identical English output.

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/kinship.ex
git commit -m "Wire Label.format into Kinship.calculate and path labels"
```

---

### Task 6: Update the directional label in the template

The template currently has a hardcoded English sentence. Update it to be translatable.

**Files:**
- Modify: `lib/web/live/kinship_live.html.heex`

- [ ] **Step 1: Update the directional label to use gettext**

```heex
<%!-- Replace: --%>
{Ancestry.People.Person.display_name(@person_a)} is {Ancestry.People.Person.display_name(
  @person_b
)}'s {String.downcase(kinship.relationship)}

<%!-- With: --%>
{gettext("%{person_a} is %{person_b}'s %{relationship}",
  person_a: Ancestry.People.Person.display_name(@person_a),
  person_b: Ancestry.People.Person.display_name(@person_b),
  relationship: String.downcase(kinship.relationship)
)}
```

- [ ] **Step 2: Add Spanish translation for the directional label**

Add to `es-UY/default.po`:

```po
msgid "%{person_a} is %{person_b}'s %{relationship}"
msgstr "%{person_a} es %{relationship} de %{person_b}"
```

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/kinship_live.html.heex priv/gettext/
git commit -m "Translate kinship directional label"
```

---

### Task 7: Run `mix gettext.extract --merge` and `mix precommit`

**Files:**
- Modify: `priv/gettext/**/*.po` (auto-updated by gettext extract)

- [ ] **Step 1: Extract and merge gettext**

Run: `mix gettext.extract --merge`

This will add any new `pgettext` msgids to the POT and PO files. Review the diff to ensure no existing translations were lost.

- [ ] **Step 2: Fill in any missing Spanish translations**

Check `priv/gettext/es-UY/LC_MESSAGES/default.po` for empty `msgstr ""` entries from the new pgettext calls. Fill them all in using the tables from `GENEALOGY.md`.

- [ ] **Step 3: Run precommit**

Run: `mix precommit`

Fix any warnings or test failures.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext/ lib/
git commit -m "Extract gettext, fill Spanish translations, pass precommit"
```

---

### Task 8: E2E test for gendered kinship labels

**Files:**
- Create: `test/user_flows/kinship_gendered_labels_test.exs`

- [ ] **Step 1: Write E2E test**

Create a test that:
1. Sets up a family with gendered persons (male grandparent, female grandparent, etc.)
2. Navigates to the kinship page
3. Selects two persons
4. Asserts the relationship label is correctly gendered
5. Tests in both English and Spanish locale

Follow the patterns in `test/user_flows/CLAUDE.md`.

- [ ] **Step 2: Run the E2E test**

Run: `mix test test/user_flows/kinship_gendered_labels_test.exs --trace`

- [ ] **Step 3: Fix any issues and commit**

```bash
git add test/user_flows/kinship_gendered_labels_test.exs
git commit -m "Add E2E test for gendered kinship labels"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `mix precommit`

- [ ] **Step 2: Manual verification**

Start the dev server: `iex -S mix phx.server`

1. Navigate to the kinship page
2. Select two people with known relationships
3. Verify labels are correctly gendered in Spanish
4. Verify labels are still correct in English
5. Check path labels show proper gendered forms

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Gendered direction-aware kinship labels complete"
```
