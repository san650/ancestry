# In-Law Kinship — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect in-law relationships (familia política) via single partner-hop BFS and display them in the kinship calculator when no blood MRCA exists.

**Architecture:** New `Ancestry.Kinship.InLaw` module checks direct spouse, then tries partner-hop BFS reusing the existing `Kinship.build_ancestor_map/1` (made public). A new `Ancestry.Kinship.InLaw.Label` module produces gendered in-law labels via Gettext for core terms (Suegro/a, Yerno/Nuera, Cuñado/a) and programmatic construction for extended terms (blood label + "político/a"). The LiveView falls back to `InLaw.calculate/2` when blood BFS returns `:no_common_ancestor`, and `push_patch` drives URL sharing.

**Tech Stack:** Elixir Gettext (`pgettext`), Phoenix LiveView, existing `Ancestry.Kinship` + `Ancestry.Relationships` modules.

**Reference:** `GENEALOGY.md` — "In-Laws — Familia Política" section. Design spec: `docs/plans/2026-04-19-in-law-kinship-design.md`.

---

### Task 1: Make `build_ancestor_map/1` public and add `get_all_partners/1`

**Files:**
- Modify: `lib/ancestry/kinship.ex:96` — change `defp build_ancestor_map` to `def build_ancestor_map`
- Modify: `lib/ancestry/relationships.ex` — add `get_all_partners/1`

- [ ] **Step 1: Make `build_ancestor_map/1` public**

In `lib/ancestry/kinship.ex`, change line 96 from `defp` to `def` and add a `@doc`:

```elixir
@doc """
Build an ancestor map using BFS. Returns %{person_id => {depth, path_from_start}}
where path_from_start is the list of person IDs from the starting person to this ancestor.
"""
def build_ancestor_map(person_id) do
  initial = %{person_id => {0, [person_id]}}
  bfs_expand([person_id], initial, 1)
end
```

- [ ] **Step 2: Add `get_all_partners/1` to `Relationships`**

In `lib/ancestry/relationships.ex`, add after `get_former_partners/2` (line 170):

```elixir
@doc """
Returns list of `{person, relationship}` tuples for all partners (active + former).
"""
def get_all_partners(person_id) do
  get_relationship_partners(person_id, Relationship.partner_types(), [])
end
```

- [ ] **Step 3: Run existing tests to verify no breakage**

Run: `mix test test/ancestry/kinship_test.exs`
Expected: All existing tests PASS (making a function public doesn't break callers).

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/kinship.ex lib/ancestry/relationships.ex
git commit -m "Make build_ancestor_map/1 public, add get_all_partners/1"
```

---

### Task 2: Create `InLaw.Label` module with core special terms

**Files:**
- Create: `lib/ancestry/kinship/in_law_label.ex`
- Create: `test/ancestry/kinship/in_law_label_test.exs`

- [ ] **Step 1: Write tests for core special terms (English locale)**

```elixir
# test/ancestry/kinship/in_law_label_test.exs
defmodule Ancestry.Kinship.InLawLabelTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLawLabel

  describe "format/3 - spouse" do
    test "spouse label" do
      assert InLawLabel.format(:spouse, :spouse, "male") == "Spouse"
      assert InLawLabel.format(:spouse, :spouse, "female") == "Spouse"
      assert InLawLabel.format(:spouse, :spouse, nil) == "Spouse"
    end
  end

  describe "format/3 - core special terms" do
    test "parent-in-law" do
      assert InLawLabel.format(0, 1, "male") == "Parent-in-law"
      assert InLawLabel.format(0, 1, "female") == "Parent-in-law"
    end

    test "child-in-law" do
      assert InLawLabel.format(1, 0, "male") == "Child-in-law"
      assert InLawLabel.format(1, 0, "female") == "Child-in-law"
    end

    test "sibling-in-law" do
      assert InLawLabel.format(1, 1, "male") == "Sibling-in-law"
      assert InLawLabel.format(1, 1, "female") == "Sibling-in-law"
    end
  end

  describe "format/3 - extended in-law terms (English)" do
    test "grandparent-in-law" do
      assert InLawLabel.format(0, 2, "male") == "Grandparent-in-law"
    end

    test "grandchild-in-law" do
      assert InLawLabel.format(2, 0, "male") == "Grandchild-in-law"
    end

    test "uncle/aunt-in-law" do
      assert InLawLabel.format(1, 2, "male") == "Uncle/Aunt-in-law"
    end

    test "nephew/niece-in-law" do
      assert InLawLabel.format(2, 1, "male") == "Nephew/Niece-in-law"
    end

    test "cousin-in-law" do
      assert InLawLabel.format(2, 2, "male") == "Cousin-in-law"
    end

    test "great grandparent-in-law" do
      assert InLawLabel.format(0, 3, "male") == "Great Grandparent-in-law"
    end

    test "great uncle/aunt-in-law" do
      assert InLawLabel.format(1, 3, "male") == "Great Uncle/Aunt-in-law"
    end

    test "grand nephew/niece-in-law" do
      assert InLawLabel.format(3, 1, "male") == "Grand Nephew/Niece-in-law"
    end

    test "second cousin-in-law" do
      assert InLawLabel.format(3, 3, "male") =~ "Cousin-in-law"
    end

    test "removed cousin-in-law" do
      # 1st cousin once removed in-law
      assert InLawLabel.format(2, 3, "male") =~ "Cousin"
      assert InLawLabel.format(2, 3, "male") =~ "-in-law"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/kinship/in_law_label_test.exs`
Expected: FAIL — module `InLawLabel` does not exist.

- [ ] **Step 3: Implement `InLawLabel` module**

Create `lib/ancestry/kinship/in_law_label.ex`. The module uses Gettext `pgettext` for core terms and constructs extended labels. For English extended terms, it uses the same Gettext approach as `Kinship.Label`. For Spanish, it constructs the blood label programmatically and appends "político/a".

```elixir
defmodule Ancestry.Kinship.InLawLabel do
  @moduledoc """
  Produces human-readable in-law kinship labels.

  Core terms (Suegro/a, Yerno/Nuera, Cuñado/a) use dedicated Gettext msgids.
  Extended terms construct the blood label then append "político/a" / "-in-law".

  The label describes "what person A is to person B" — gendered by person A's gender.
  """

  defp normalize_gender("male"), do: "male"
  defp normalize_gender("female"), do: "female"
  defp normalize_gender(_), do: "other"

  defp t(g, msgid), do: Gettext.pgettext(Web.Gettext, g, msgid)
  defp t(g, msgid, bindings), do: Gettext.pgettext(Web.Gettext, g, msgid, bindings)

  @doc """
  Formats an in-law label.

  For spouse: pass `(:spouse, :spouse, gender)`.
  For partner-hop results: pass `(steps_a, steps_b, gender)` from the blood BFS.
  """
  def format(:spouse, :spouse, gender) do
    g = normalize_gender(gender)
    t(g, "Spouse")
  end

  def format(steps_a, steps_b, gender) do
    g = normalize_gender(gender)
    classify(steps_a, steps_b, g)
  end

  # Core special terms
  defp classify(0, 1, g), do: t(g, "Parent-in-law")
  defp classify(1, 0, g), do: t(g, "Child-in-law")
  defp classify(1, 1, g), do: t(g, "Sibling-in-law")

  # Everything else — locale-aware
  defp classify(steps_a, steps_b, g) do
    locale = Gettext.get_locale(Web.Gettext)

    if String.starts_with?(locale, "es") do
      spanish_in_law_label(steps_a, steps_b, g)
    else
      english_in_law_label(steps_a, steps_b, g)
    end
  end

  # --- English in-law labels ---

  # Direct line ascending
  defp english_in_law_label(0, 2, g), do: t(g, "Grandparent-in-law")
  defp english_in_law_label(0, 3, g), do: t(g, "Great Grandparent-in-law")
  defp english_in_law_label(0, 4, g), do: t(g, "Great Great Grandparent-in-law")
  defp english_in_law_label(0, 5, g), do: t(g, "3rd Great Grandparent-in-law")

  defp english_in_law_label(0, steps_b, g) when steps_b >= 6 do
    t(g, "%{nth} Great Grandparent-in-law", nth: numeric_ordinal(steps_b - 2))
  end

  # Direct line descending
  defp english_in_law_label(2, 0, g), do: t(g, "Grandchild-in-law")
  defp english_in_law_label(3, 0, g), do: t(g, "Great Grandchild-in-law")
  defp english_in_law_label(4, 0, g), do: t(g, "Great Great Grandchild-in-law")
  defp english_in_law_label(5, 0, g), do: t(g, "3rd Great Grandchild-in-law")

  defp english_in_law_label(steps_a, 0, g) when steps_a >= 6 do
    t(g, "%{nth} Great Grandchild-in-law", nth: numeric_ordinal(steps_a - 2))
  end

  # Uncle/Aunt chain
  defp english_in_law_label(1, 2, g), do: t(g, "Uncle/Aunt-in-law")
  defp english_in_law_label(1, 3, g), do: t(g, "Great Uncle/Aunt-in-law")
  defp english_in_law_label(1, 4, g), do: t(g, "Great Grand Uncle/Aunt-in-law")

  defp english_in_law_label(1, steps_b, g) when steps_b >= 5 do
    t(g, "%{nth} Great Grand Uncle/Aunt-in-law", nth: numeric_ordinal(steps_b - 4))
  end

  # Nephew/Niece chain
  defp english_in_law_label(2, 1, g), do: t(g, "Nephew/Niece-in-law")
  defp english_in_law_label(3, 1, g), do: t(g, "Grand Nephew/Niece-in-law")
  defp english_in_law_label(4, 1, g), do: t(g, "Great Grand Nephew/Niece-in-law")

  defp english_in_law_label(steps_a, 1, g) when steps_a >= 5 do
    t(g, "%{nth} Great Grand Nephew/Niece-in-law", nth: numeric_ordinal(steps_a - 4))
  end

  # Cousins (same gen and removed)
  defp english_in_law_label(steps_a, steps_b, g) when steps_a >= 2 and steps_b >= 2 do
    degree = min(steps_a, steps_b) - 1
    degree_str = ordinal(degree, g)

    if steps_a == steps_b do
      t(g, "%{degree} Cousin-in-law", degree: degree_str)
    else
      removed = abs(steps_a - steps_b)

      removed_str =
        cond do
          removed == 1 -> t(g, ", Once Removed")
          removed == 2 -> t(g, ", Twice Removed")
          true -> t(g, ", %{count} Times Removed", count: removed)
        end

      t(g, "%{degree} Cousin%{removed}-in-law", degree: degree_str, removed: removed_str)
    end
  end

  # --- Spanish in-law labels ---
  # Constructs blood label programmatically, appends "político/a"

  defp spanish_in_law_label(steps_a, steps_b, g) do
    blood = spanish_blood_label(steps_a, steps_b, g)
    suffix = politico_suffix(g)
    "#{blood} #{suffix}"
  end

  # Direct line ascending
  defp spanish_blood_label(0, 1, g), do: spanish_parent(g)
  defp spanish_blood_label(0, 2, g), do: spanish_abuelo(g)
  defp spanish_blood_label(0, 3, g), do: spanish_bisabuelo(g)
  defp spanish_blood_label(0, 4, g), do: spanish_tatarabuelo(g)
  defp spanish_blood_label(0, 5, g), do: spanish_trastatarabuelo(g)

  defp spanish_blood_label(0, steps_b, g) when steps_b >= 6,
    do: "#{steps_b - 1}° #{spanish_abuelo(g)}"

  # Direct line descending
  defp spanish_blood_label(1, 0, g), do: spanish_child(g)
  defp spanish_blood_label(2, 0, g), do: spanish_nieto(g)
  defp spanish_blood_label(3, 0, g), do: spanish_bisnieto(g)
  defp spanish_blood_label(4, 0, g), do: spanish_tataranieto(g)
  defp spanish_blood_label(5, 0, g), do: spanish_trastataranieto(g)

  defp spanish_blood_label(steps_a, 0, g) when steps_a >= 6,
    do: "#{steps_a - 1}° #{spanish_nieto(g)}"

  # Siblings
  defp spanish_blood_label(1, 1, g), do: spanish_hermano(g)

  # Uncle/Aunt and Nephew/Niece chains + cousins
  defp spanish_blood_label(steps_a, steps_b, g) when steps_a >= 1 and steps_b >= 1 do
    if steps_a == steps_b and steps_a >= 2 do
      spanish_cousin(steps_a, g)
    else
      spanish_removed_label(steps_a, steps_b, g)
    end
  end

  defp spanish_cousin(steps, g) do
    degree = steps - 1
    base = if g == "female", do: "Prima", else: "Primo"
    ord = spanish_ordinal_suffix(degree, g)

    [base, ord]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp spanish_removed_label(steps_a, steps_b, g) do
    ordinal_n = min(steps_a, steps_b)
    removed = abs(steps_a - steps_b)
    direction = if steps_a < steps_b, do: :ascending, else: :descending

    base = spanish_base(direction, g)
    gen_suffix = spanish_generation_suffix(direction, removed, g)
    ord_suffix = spanish_ordinal_suffix(ordinal_n, g)

    [base, gen_suffix, ord_suffix]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  # --- Spanish helpers (mirrored from Kinship.Label) ---

  defp politico_suffix("male"), do: "político"
  defp politico_suffix("female"), do: "política"
  defp politico_suffix(_), do: "político/a"

  defp spanish_parent("male"), do: "Padre"
  defp spanish_parent("female"), do: "Madre"
  defp spanish_parent(_), do: "Padre/Madre"

  defp spanish_child("male"), do: "Hijo"
  defp spanish_child("female"), do: "Hija"
  defp spanish_child(_), do: "Hijo/a"

  defp spanish_hermano("male"), do: "Hermano"
  defp spanish_hermano("female"), do: "Hermana"
  defp spanish_hermano(_), do: "Hermano/a"

  defp spanish_abuelo("female"), do: "Abuela"
  defp spanish_abuelo(_), do: "Abuelo"

  defp spanish_bisabuelo("female"), do: "Bisabuela"
  defp spanish_bisabuelo(_), do: "Bisabuelo"

  defp spanish_tatarabuelo("female"), do: "Tatarabuela"
  defp spanish_tatarabuelo(_), do: "Tatarabuelo"

  defp spanish_trastatarabuelo("female"), do: "Trastatarabuela"
  defp spanish_trastatarabuelo(_), do: "Trastatarabuelo"

  defp spanish_nieto("female"), do: "Nieta"
  defp spanish_nieto(_), do: "Nieto"

  defp spanish_bisnieto("female"), do: "Bisnieta"
  defp spanish_bisnieto(_), do: "Bisnieto"

  defp spanish_tataranieto("female"), do: "Tataranieta"
  defp spanish_tataranieto(_), do: "Tataranieto"

  defp spanish_trastataranieto("female"), do: "Trastataranieta"
  defp spanish_trastataranieto(_), do: "Trastataranieto"

  defp spanish_base(:ascending, "male"), do: "Tío"
  defp spanish_base(:ascending, "female"), do: "Tía"
  defp spanish_base(:ascending, _), do: "Tío/a"
  defp spanish_base(:descending, "male"), do: "Sobrino"
  defp spanish_base(:descending, "female"), do: "Sobrina"
  defp spanish_base(:descending, _), do: "Sobrino/a"

  defp spanish_generation_suffix(_direction, 1, _g), do: ""
  defp spanish_generation_suffix(:ascending, 2, "female"), do: "abuela"
  defp spanish_generation_suffix(:ascending, 2, _), do: "abuelo"
  defp spanish_generation_suffix(:ascending, 3, "female"), do: "bisabuela"
  defp spanish_generation_suffix(:ascending, 3, _), do: "bisabuelo"
  defp spanish_generation_suffix(:ascending, 4, "female"), do: "tatarabuela"
  defp spanish_generation_suffix(:ascending, 4, _), do: "tatarabuelo"
  defp spanish_generation_suffix(:ascending, 5, "female"), do: "trastatarabuela"
  defp spanish_generation_suffix(:ascending, 5, _), do: "trastatarabuelo"
  defp spanish_generation_suffix(:ascending, n, "female") when n >= 6, do: "#{n}° abuela"
  defp spanish_generation_suffix(:ascending, n, _) when n >= 6, do: "#{n}° abuelo"
  defp spanish_generation_suffix(:descending, 2, "female"), do: "nieta"
  defp spanish_generation_suffix(:descending, 2, _), do: "nieto"
  defp spanish_generation_suffix(:descending, 3, "female"), do: "bisnieta"
  defp spanish_generation_suffix(:descending, 3, _), do: "bisnieto"
  defp spanish_generation_suffix(:descending, 4, "female"), do: "tataranieta"
  defp spanish_generation_suffix(:descending, 4, _), do: "tataranieto"
  defp spanish_generation_suffix(:descending, 5, "female"), do: "trastataranieta"
  defp spanish_generation_suffix(:descending, 5, _), do: "trastataranieto"
  defp spanish_generation_suffix(:descending, n, "female") when n >= 6, do: "#{n}° nieta"
  defp spanish_generation_suffix(:descending, n, _) when n >= 6, do: "#{n}° nieto"

  defp spanish_ordinal_suffix(1, _g), do: ""
  defp spanish_ordinal_suffix(2, "female"), do: "segunda"
  defp spanish_ordinal_suffix(2, _), do: "segundo"
  defp spanish_ordinal_suffix(3, "female"), do: "tercera"
  defp spanish_ordinal_suffix(3, _), do: "tercero"
  defp spanish_ordinal_suffix(4, "female"), do: "cuarta"
  defp spanish_ordinal_suffix(4, _), do: "cuarto"
  defp spanish_ordinal_suffix(5, "female"), do: "quinta"
  defp spanish_ordinal_suffix(5, _), do: "quinto"
  defp spanish_ordinal_suffix(6, "female"), do: "sexta"
  defp spanish_ordinal_suffix(6, _), do: "sexto"
  defp spanish_ordinal_suffix(7, "female"), do: "séptima"
  defp spanish_ordinal_suffix(7, _), do: "séptimo"
  defp spanish_ordinal_suffix(8, "female"), do: "octava"
  defp spanish_ordinal_suffix(8, _), do: "octavo"
  defp spanish_ordinal_suffix(n, _), do: "#{n}°"

  defp ordinal(1, g), do: t(g, "First")
  defp ordinal(2, g), do: t(g, "Second")
  defp ordinal(3, g), do: t(g, "Third")
  defp ordinal(4, g), do: t(g, "Fourth")
  defp ordinal(5, g), do: t(g, "Fifth")
  defp ordinal(6, g), do: t(g, "Sixth")
  defp ordinal(7, g), do: t(g, "Seventh")
  defp ordinal(8, g), do: t(g, "Eighth")
  defp ordinal(n, _g), do: "#{n}th"

  defp numeric_ordinal(1), do: "1st"
  defp numeric_ordinal(2), do: "2nd"
  defp numeric_ordinal(3), do: "3rd"
  defp numeric_ordinal(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n}st"
  defp numeric_ordinal(n) when rem(n, 10) == 2 and rem(n, 100) != 12, do: "#{n}nd"
  defp numeric_ordinal(n) when rem(n, 10) == 3 and rem(n, 100) != 13, do: "#{n}rd"
  defp numeric_ordinal(n), do: "#{n}th"
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/in_law_label_test.exs`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/in_law_label.ex test/ancestry/kinship/in_law_label_test.exs
git commit -m "Add InLawLabel module with core and extended in-law labels"
```

---

### Task 3: Add Spanish in-law label tests and Gettext translations

**Files:**
- Modify: `test/ancestry/kinship/in_law_label_test.exs`
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po`
- Modify: `priv/gettext/en-US/LC_MESSAGES/default.po`

- [ ] **Step 1: Add Spanish label tests**

Append to `test/ancestry/kinship/in_law_label_test.exs`:

```elixir
describe "format/3 - Spanish locale" do
  setup do
    Gettext.put_locale(Web.Gettext, "es-UY")
    on_exit(fn -> Gettext.put_locale(Web.Gettext, "en") end)
  end

  test "spouse — male" do
    assert InLawLabel.format(:spouse, :spouse, "male") == "Esposo"
  end

  test "spouse — female" do
    assert InLawLabel.format(:spouse, :spouse, "female") == "Esposa"
  end

  test "parent-in-law — male (suegro)" do
    assert InLawLabel.format(0, 1, "male") == "Suegro"
  end

  test "parent-in-law — female (suegra)" do
    assert InLawLabel.format(0, 1, "female") == "Suegra"
  end

  test "child-in-law — male (yerno)" do
    assert InLawLabel.format(1, 0, "male") == "Yerno"
  end

  test "child-in-law — female (nuera)" do
    assert InLawLabel.format(1, 0, "female") == "Nuera"
  end

  test "sibling-in-law — male (cuñado)" do
    assert InLawLabel.format(1, 1, "male") == "Cuñado"
  end

  test "sibling-in-law — female (cuñada)" do
    assert InLawLabel.format(1, 1, "female") == "Cuñada"
  end

  test "grandparent-in-law — male (abuelo político)" do
    assert InLawLabel.format(0, 2, "male") == "Abuelo político"
  end

  test "grandparent-in-law — female (abuela política)" do
    assert InLawLabel.format(0, 2, "female") == "Abuela política"
  end

  test "uncle-in-law — male (tío político)" do
    assert InLawLabel.format(1, 2, "male") == "Tío político"
  end

  test "aunt-in-law — female (tía política)" do
    assert InLawLabel.format(1, 2, "female") == "Tía política"
  end

  test "nephew-in-law — male (sobrino político)" do
    assert InLawLabel.format(2, 1, "male") == "Sobrino político"
  end

  test "cousin-in-law — male (primo político)" do
    assert InLawLabel.format(2, 2, "male") == "Primo político"
  end

  test "cousin-in-law — female (prima política)" do
    assert InLawLabel.format(2, 2, "female") == "Prima política"
  end

  test "great uncle-in-law — male (tío abuelo político)" do
    assert InLawLabel.format(1, 3, "male") == "Tío abuelo político"
  end

  test "removed cousin in-law — tío segundo político" do
    assert InLawLabel.format(2, 3, "male") == "Tío segundo político"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail (missing translations)**

Run: `mix test test/ancestry/kinship/in_law_label_test.exs`
Expected: Spanish tests FAIL — Gettext falls back to English msgids.

- [ ] **Step 3: Extract Gettext and add translations**

Run: `mix gettext.extract --merge`

Then add the in-law entries to `priv/gettext/es-UY/LC_MESSAGES/default.po` with gendered `msgctxt`. Add the 4 core special terms with all 3 gender contexts:

```po
msgctxt "male"
msgid "Spouse"
msgstr "Esposo"

msgctxt "female"
msgid "Spouse"
msgstr "Esposa"

msgctxt "other"
msgid "Spouse"
msgstr "Cónyuge"

msgctxt "male"
msgid "Parent-in-law"
msgstr "Suegro"

msgctxt "female"
msgid "Parent-in-law"
msgstr "Suegra"

msgctxt "other"
msgid "Parent-in-law"
msgstr "Suegro/a"

msgctxt "male"
msgid "Child-in-law"
msgstr "Yerno"

msgctxt "female"
msgid "Child-in-law"
msgstr "Nuera"

msgctxt "other"
msgid "Child-in-law"
msgstr "Yerno/Nuera"

msgctxt "male"
msgid "Sibling-in-law"
msgstr "Cuñado"

msgctxt "female"
msgid "Sibling-in-law"
msgstr "Cuñada"

msgctxt "other"
msgid "Sibling-in-law"
msgstr "Cuñado/a"
```

Also add gendered entries to `priv/gettext/en-US/LC_MESSAGES/default.po` for the core terms:

```po
msgctxt "male"
msgid "Spouse"
msgstr "Husband"

msgctxt "female"
msgid "Spouse"
msgstr "Wife"

msgctxt "other"
msgid "Spouse"
msgstr "Spouse"

msgctxt "male"
msgid "Parent-in-law"
msgstr "Father-in-law"

msgctxt "female"
msgid "Parent-in-law"
msgstr "Mother-in-law"

msgctxt "male"
msgid "Child-in-law"
msgstr "Son-in-law"

msgctxt "female"
msgid "Child-in-law"
msgstr "Daughter-in-law"

msgctxt "male"
msgid "Sibling-in-law"
msgstr "Brother-in-law"

msgctxt "female"
msgid "Sibling-in-law"
msgstr "Sister-in-law"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/in_law_label_test.exs`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add test/ancestry/kinship/in_law_label_test.exs priv/gettext/
git commit -m "Add Spanish in-law label translations and tests"
```

---

### Task 4: Create `InLaw` module with partner-hop algorithm

**Files:**
- Create: `lib/ancestry/kinship/in_law.ex`
- Create: `test/ancestry/kinship/in_law_test.exs`

- [ ] **Step 1: Write tests for the InLaw algorithm**

```elixir
# test/ancestry/kinship/in_law_test.exs
defmodule Ancestry.Kinship.InLawTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLaw
  alias Ancestry.People
  alias Ancestry.Relationships

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  defp family_fixture do
    org = org_fixture()
    {:ok, family} = Ancestry.Families.create_family(org, %{name: "Test Family"})
    family
  end

  defp person_fixture(family, attrs) do
    {:ok, person} = People.create_person(family, attrs)
    person
  end

  defp make_parent!(parent, child) do
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
  end

  defp make_partner!(a, b, type \\ "married") do
    {:ok, _} = Relationships.create_relationship(a, b, type, %{})
  end

  describe "calculate/2 - direct spouse" do
    test "returns spouse for married couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      assert {:ok, %InLaw{relationship: "Spouse"}} = InLaw.calculate(alice.id, bob.id)
    end

    test "returns spouse for divorced couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob, "divorced")

      assert {:ok, %InLaw{}} = InLaw.calculate(alice.id, bob.id)
    end
  end

  describe "calculate/2 - parent-in-law" do
    test "spouse's parent is parent-in-law" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      # Father is Wife's parent-in-law (father-in-law)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id)
      assert result.relationship == "Parent-in-law"
    end
  end

  describe "calculate/2 - sibling-in-law" do
    test "spouse's sibling is sibling-in-law" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      daughter = person_fixture(family, %{given_name: "Daughter", surname: "S", gender: "female"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(parent, son)
      make_parent!(parent, daughter)
      make_partner!(son, wife)

      # Daughter is Wife's sibling-in-law (sister-in-law)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(daughter.id, wife.id)
      assert result.relationship == "Sibling-in-law"
    end
  end

  describe "calculate/2 - extended in-law (nephew-in-law)" do
    test "sibling's child's partner is nephew-in-law scenario" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      uncle = person_fixture(family, %{given_name: "Uncle", surname: "S", gender: "male"})
      nephew = person_fixture(family, %{given_name: "Nephew", surname: "S", gender: "male"})
      partner = person_fixture(family, %{given_name: "Partner", surname: "S", gender: "female"})
      make_parent!(parent, uncle)
      make_parent!(parent, nephew)
      make_partner!(nephew, partner)

      # Uncle to Partner: uncle is nephew's sibling, nephew is Partner's partner
      # So Uncle is Partner's uncle-in-law
      assert {:ok, %InLaw{}} = InLaw.calculate(uncle.id, partner.id)
    end
  end

  describe "calculate/2 - no relationship" do
    test "returns error when no in-law path exists" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})

      assert {:error, :no_relationship} = InLaw.calculate(alice.id, bob.id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/kinship/in_law_test.exs`
Expected: FAIL — module `InLaw` does not exist.

- [ ] **Step 3: Implement the `InLaw` module**

Create `lib/ancestry/kinship/in_law.ex` following the algorithm from the design spec. The module:

1. Checks direct spouse via `Relationships.get_partner_relationship/2`
2. Gets all partners of A, runs blood BFS for each against B
3. Gets all partners of B, runs blood BFS for A against each
4. Picks shortest path, constructs label with `InLawLabel.format/3`
5. Builds path with `partner_link?` annotations

Key implementation details:
- Uses `Kinship.build_ancestor_map/1` (now public) for BFS
- Uses `Relationships.get_all_partners/1` for partner queries
- The `find_mrca/2` helper extracts the MRCA-finding logic from `Kinship.calculate/2`
- Path nodes include `partner_link?: true` for the partner pair

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/kinship/in_law_test.exs`
Expected: All PASS.

- [ ] **Step 5: Run all kinship tests**

Run: `mix test test/ancestry/kinship_test.exs test/ancestry/kinship/`
Expected: All PASS — existing blood kinship tests unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/kinship/in_law.ex test/ancestry/kinship/in_law_test.exs
git commit -m "Add InLaw module with partner-hop BFS algorithm"
```

---

### Task 5: Wire InLaw into KinshipLive and refactor to push_patch

**Files:**
- Modify: `lib/web/live/kinship_live.ex`

- [ ] **Step 1: Refactor event handlers to use push_patch**

In `lib/web/live/kinship_live.ex`, change `select_person_a`, `select_person_b`, `clear_a`, `clear_b`, and `swap` handlers to use `push_patch` instead of direct assignment + `maybe_calculate()`. Let `handle_params` be the single entry point for calculation:

```elixir
def handle_event("select_person_a", %{"id" => id}, socket) do
  person = find_person(socket.assigns.people, id)

  {:noreply,
   socket
   |> assign(:dropdown_a, false)
   |> assign(:search_a, "")
   |> push_kinship_patch(person, socket.assigns.person_b)}
end

def handle_event("select_person_b", %{"id" => id}, socket) do
  person = find_person(socket.assigns.people, id)

  {:noreply,
   socket
   |> assign(:dropdown_b, false)
   |> assign(:search_b, "")
   |> push_kinship_patch(socket.assigns.person_a, person)}
end

def handle_event("clear_a", _, socket) do
  {:noreply, push_kinship_patch(socket, nil, socket.assigns.person_b)}
end

def handle_event("clear_b", _, socket) do
  {:noreply, push_kinship_patch(socket, socket.assigns.person_a, nil)}
end

def handle_event("swap", _, socket) do
  {:noreply, push_kinship_patch(socket, socket.assigns.person_b, socket.assigns.person_a)}
end

defp push_kinship_patch(socket, person_a, person_b) do
  params =
    %{}
    |> then(fn p -> if person_a, do: Map.put(p, :person_a, person_a.id), else: p end)
    |> then(fn p -> if person_b, do: Map.put(p, :person_b, person_b.id), else: p end)

  push_patch(socket, to: ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}/kinship?#{params}")
end
```

- [ ] **Step 2: Add in-law fallback to `maybe_calculate/1`**

```elixir
defp maybe_calculate(socket) do
  case {socket.assigns.person_a, socket.assigns.person_b} do
    {%Person{id: a_id}, %Person{id: b_id}} ->
      result = Kinship.calculate(a_id, b_id)

      case result do
        {:ok, kinship} ->
          path_a = Enum.slice(kinship.path, 0, kinship.steps_a + 1) |> Enum.reverse()
          path_b = Enum.slice(kinship.path, kinship.steps_a, length(kinship.path) - kinship.steps_a)

          socket
          |> assign(:result, result)
          |> assign(:path_a, path_a)
          |> assign(:path_b, path_b)

        {:error, :no_common_ancestor} ->
          in_law_result = Ancestry.Kinship.InLaw.calculate(a_id, b_id)

          case in_law_result do
            {:ok, in_law} ->
              socket
              |> assign(:result, in_law_result)
              |> assign(:path_a, in_law.path)
              |> assign(:path_b, [])

            {:error, _} ->
              socket
              |> assign(:result, {:error, :no_relationship})
              |> assign(:path_a, [])
              |> assign(:path_b, [])
          end

        error ->
          socket
          |> assign(:result, error)
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

Add `alias Ancestry.Kinship.InLaw` at the top of the module.

- [ ] **Step 3: Run existing E2E tests to check push_patch refactor**

Run: `mix test test/user_flows/calculating_kinship_test.exs test/user_flows/kinship_gendered_labels_test.exs`
Expected: May FAIL on "No common ancestor found" text assertion — fix in next task.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/kinship_live.ex
git commit -m "Wire InLaw fallback into KinshipLive, refactor to push_patch"
```

---

### Task 6: Update template for in-law results

**Files:**
- Modify: `lib/web/live/kinship_live.html.heex`
- Modify: `test/user_flows/calculating_kinship_test.exs`

- [ ] **Step 1: Add in-law result branch to template**

In `lib/web/live/kinship_live.html.heex`, add a new `cond` branch before the `no_common_ancestor` check (around line 126). The in-law branch matches on `%Ancestry.Kinship.InLaw{}`:

```heex
<% match?({:ok, %Ancestry.Kinship.InLaw{}}, @result) -> %>
  <% {:ok, in_law} = @result %>
  <div {test_id("kinship-in-law-result")}>
    <%!-- Relationship label --%>
    <div class="text-center mb-2">
      <span class="text-3xl font-ds-heading font-extrabold text-ds-primary"
        {test_id("kinship-relationship-label")}>
        {in_law.relationship}
      </span>
    </div>

    <%!-- "Related by marriage" note --%>
    <div class="text-center mb-2">
      <span class="text-sm text-ds-on-surface-variant"
        {test_id("kinship-in-law-note")}>
        {gettext("Related by marriage")}
      </span>
    </div>

    <%!-- Directional label --%>
    <div class="text-center mb-8">
      <span class="text-base text-ds-on-surface-variant"
        {test_id("kinship-directional-label")}>
        {gettext("%{person_a} is %{person_b}'s %{relationship}",
          person_a: Person.display_name(@person_a),
          person_b: Person.display_name(@person_b),
          relationship: String.downcase(in_law.relationship)
        )}
      </span>
    </div>

    <%!-- Linear path visualization --%>
    <div class="flex flex-col items-center" {test_id("kinship-path")}>
      <%= for {node, index} <- Enum.with_index(@path_a) do %>
        <%= if index > 0 do %>
          <%= if Enum.at(@path_a, index - 1)[:partner_link?] && node[:partner_link?] do %>
            <%!-- Partner connector --%>
            <div class="py-1 text-ds-primary/50">
              <.icon name="hero-heart" class="w-4 h-4 mx-auto" />
            </div>
          <% else %>
            <.arrow_connector direction={:down} />
          <% end %>
        <% end %>
        <% is_endpoint = index == 0 or index == length(@path_a) - 1 %>
        <div class={[
          "flex items-center gap-3 px-4 py-3 rounded-ds-sharp border w-full max-w-sm",
          if(is_endpoint,
            do: "bg-ds-primary/10 border-ds-primary/30",
            else: "bg-ds-surface-low/50 border-ds-outline-variant/20"
          )
        ]}>
          <.kinship_person_avatar person={node.person} />
          <div class="min-w-0 flex-1">
            <p class="font-medium text-sm text-ds-on-surface truncate">
              {Person.display_name(node.person)}
            </p>
            <p class="text-xs text-ds-on-surface-variant">{node.label}</p>
          </div>
        </div>
      <% end %>
    </div>
  </div>
```

- [ ] **Step 2: Update error state text**

Change the `no_common_ancestor` branch to also match `:no_relationship`:

```heex
<% match?({:error, :no_common_ancestor}, @result) or match?({:error, :no_relationship}, @result) -> %>
  <div class="text-center py-12 text-ds-on-surface-variant" {test_id("kinship-no-result")}>
    <.icon name="hero-magnifying-glass" class="w-12 h-12 mx-auto mb-3" />
    <p class="text-lg font-medium">{gettext("No relationship found")}</p>
    <p class="text-sm mt-1">
      {gettext("These two people don't appear to be related by blood or marriage within the family tree")}
    </p>
  </div>
```

- [ ] **Step 3: Update existing E2E test assertion**

In `test/user_flows/calculating_kinship_test.exs:196`, change:

```elixir
# Old:
|> assert_has(test_id("kinship-no-result"), text: "No common ancestor found")
# New:
|> assert_has(test_id("kinship-no-result"), text: "No relationship found")
```

- [ ] **Step 4: Run tests**

Run: `mix test test/user_flows/calculating_kinship_test.exs test/user_flows/kinship_gendered_labels_test.exs`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/kinship_live.html.heex test/user_flows/calculating_kinship_test.exs
git commit -m "Add in-law result template branch, update error state text"
```

---

### Task 7: E2E tests for in-law kinship

**Files:**
- Create: `test/user_flows/kinship_in_law_test.exs`

- [ ] **Step 1: Write E2E tests**

Create `test/user_flows/kinship_in_law_test.exs` with test setup creating a family tree with partner relationships. The setup should create:

- A parent with two children (son + daughter)
- The son married to a wife
- This gives us: wife ↔ son (spouse), parent ↔ wife (parent-in-law), daughter ↔ wife (sibling-in-law)
- An unrelated person with no connections (for "no relationship" test)

Tests to write (matching the E2E test plan from the design spec):

1. **Direct spouse** — select son and wife → "Spouse"
2. **Parent-in-law** — select parent and wife → "Parent-in-law" / "Father-in-law"
3. **Child-in-law** — select wife and parent → verify Yerno/Nuera in Spanish
4. **Sibling-in-law** — select daughter and wife → "Sibling-in-law"
5. **No relationship** — select unrelated person and wife → "No relationship found"
6. **URL sharing** — navigate with `?person_a=ID&person_b=ID`, verify result loads
7. **Blood takes precedence** — select son and daughter (siblings by blood) → shows "Sibling" not in-law
8. **Swap reverses direction** — parent-in-law swapped becomes child-in-law
9. **Divorced partner still shows in-law** — create divorced couple, verify in-law still detected

Follow the patterns from `test/user_flows/kinship_gendered_labels_test.exs` for test structure, using `insert(:person)`, `log_in_e2e(conn)`, `test_id/1` selectors, and `click`/`assert_has` helpers.

- [ ] **Step 2: Run E2E tests**

Run: `mix test test/user_flows/kinship_in_law_test.exs`
Expected: All PASS.

- [ ] **Step 3: Run full test suite**

Run: `mix precommit`
Expected: All PASS, no warnings, no formatting issues.

- [ ] **Step 4: Commit**

```bash
git add test/user_flows/kinship_in_law_test.exs
git commit -m "Add E2E tests for in-law kinship detection"
```
