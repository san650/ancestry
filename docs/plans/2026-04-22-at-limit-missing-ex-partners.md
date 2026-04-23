# Fix: Ex-partners missing at tree depth boundary

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show all partners (active + former) for children rendered at the depth boundary in the tree view, so that ex-partners like a divorced spouse appear next to their former partner even at the truncated level.

**Architecture:** Enrich the `at_limit` stub in `PersonGraph.build_child_units_acc/5` to query all partners (not just active ones) and include non-main partners as `previous_partners`. Pass that data through to the `couple_card` component in the template.

**Tech Stack:** Elixir, Phoenix LiveView

**Spec:** `docs/bugfix/specs/2026-04-22-at-limit-missing-ex-partners-design.md`

---

### Task 1: Write failing test for ex-partners at boundary

**Files:**
- Modify: `test/ancestry/people/person_graph_test.exs`

- [ ] **Step 1: Write the failing test**

Add this test inside the existing `describe "depth controls"` block. It creates two siblings where one is divorced from a person who is currently married to the other — the exact Greta/Gilbert/Humphrey scenario. It asserts that the boundary stub for the divorced sibling includes `previous_partners` with the ex-spouse.

```elixir
test "at_limit children include ex-partners in previous_partners", %{family: family} do
  # Override the lineage setup — we need our own family structure
  family = family_fixture()

  # Parents
  {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
  {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
  {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})

  # Two sons (siblings)
  {:ok, gilbert} = People.create_person(family, %{given_name: "Gilbert", surname: "D"})
  {:ok, humphrey} = People.create_person(family, %{given_name: "Humphrey", surname: "D"})
  {:ok, _} = Relationships.create_relationship(dad, gilbert, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mom, gilbert, "parent", %{role: "mother"})
  {:ok, _} = Relationships.create_relationship(dad, humphrey, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mom, humphrey, "parent", %{role: "mother"})

  # Greta: divorced from Gilbert (married 1966, divorced 1975), married to Humphrey (1976)
  {:ok, greta} = People.create_person(family, %{given_name: "Greta", surname: "W"})

  {:ok, _} =
    Relationships.create_relationship(gilbert, greta, "divorced", %{
      marriage_year: 1966,
      divorce_year: 1975
    })

  {:ok, _} =
    Relationships.create_relationship(humphrey, greta, "married", %{marriage_year: 1976})

  # Build tree focused on Mom with descendants: 1 (children at boundary)
  tree = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

  # Find Gilbert and Humphrey in the partner_children
  children = tree.center.partner_children
  gilbert_unit = Enum.find(children, &(&1.person.id == gilbert.id))
  humphrey_unit = Enum.find(children, &(&1.person.id == humphrey.id))

  # Humphrey's main partner should be Greta (active married, his only partner)
  assert humphrey_unit.partner.id == greta.id
  assert humphrey_unit.previous_partners == []

  # Gilbert's main partner should also be Greta (divorced, but his only partner)
  # At the boundary, all partners (active + former) are treated uniformly —
  # the first by marriage year desc becomes the main partner.
  assert gilbert_unit.partner.id == greta.id
  assert gilbert_unit.previous_partners == []
end

test "at_limit children show multiple partners as main + previous_partners" do
  family = family_fixture()

  {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
  {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
  {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})

  {:ok, son} = People.create_person(family, %{given_name: "Son", surname: "D"})
  {:ok, _} = Relationships.create_relationship(dad, son, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mom, son, "parent", %{role: "mother"})

  # Son: divorced from Jane (1980), married to Mary (1990)
  {:ok, jane} = People.create_person(family, %{given_name: "Jane", surname: "W"})
  {:ok, mary} = People.create_person(family, %{given_name: "Mary", surname: "W"})

  {:ok, _} =
    Relationships.create_relationship(son, jane, "divorced", %{
      marriage_year: 1980,
      divorce_year: 1988
    })

  {:ok, _} =
    Relationships.create_relationship(son, mary, "married", %{marriage_year: 1990})

  tree = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

  children = tree.center.partner_children
  son_unit = Enum.find(children, &(&1.person.id == son.id))

  # Main partner is Mary (latest marriage year)
  assert son_unit.partner.id == mary.id
  # Jane is in previous_partners
  assert length(son_unit.previous_partners) == 1
  [prev] = son_unit.previous_partners
  assert prev.person.id == jane.id
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people/person_graph_test.exs --seed 0`

Expected: FAIL — the `at_limit` branch currently only queries `active_partners`, so:
- First test: `gilbert_unit.partner` is `nil` (Greta is divorced, not active), fails on `gilbert_unit.partner.id`
- Second test: `son_unit.previous_partners` key doesn't exist, raises `KeyError`

---

### Task 2: Fix `at_limit` branch in PersonGraph

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex:140-151`

- [ ] **Step 1: Replace the active-only partner query with all partners**

In `build_child_units_acc/5`, replace the `at_limit` branch (lines 140-151) from:

```elixir
if at_limit do
  has_more = FamilyGraph.has_children?(graph, child.id)
  partners = FamilyGraph.active_partners(graph, child.id)

  partner =
    case partners do
      [{p, _} | _] -> p
      [] -> nil
    end

  {units ++ [%{person: child, partner: partner, has_more: has_more, children: nil}],
   vis}
```

To:

```elixir
if at_limit do
  has_more = FamilyGraph.has_children?(graph, child.id)
  all_partners = FamilyGraph.all_partners(graph, child.id)

  sorted_partners =
    Enum.sort_by(
      all_partners,
      fn {p, rel} ->
        year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
        {year || 0, p.id}
      end,
      :desc
    )

  {partner, previous} =
    case sorted_partners do
      [{p, _rel} | rest] -> {p, rest}
      [] -> {nil, []}
    end

  previous_partners = Enum.map(previous, fn {p, _rel} -> %{person: p} end)

  {units ++
     [%{person: child, partner: partner, previous_partners: previous_partners,
        has_more: has_more, children: nil}], vis}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `mix test test/ancestry/people/person_graph_test.exs --seed 0`

Expected: PASS — both tests pass. Gilbert's stub now includes `partner: greta`. Son's stub includes `partner: mary` and `previous_partners: [%{person: jane}]`.

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `mix test`

Expected: All tests pass. Existing tests that read `at_limit` stubs (like `"default opts"` at line 277) access `kid_unit.person` and `kid_unit.children` — they don't assert on `previous_partners`, so they're unaffected by the new key.

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Fix at_limit boundary to include all partners (active + former)

The at_limit code path only queried active_partners, dropping
divorced/separated partners entirely. Now uses all_partners and
sorts them into main partner + previous_partners, matching the
shape that build_family_unit_full produces."
```

---

### Task 3: Pass `previous_partners` through in the template

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex:293-322`

- [ ] **Step 1: Add `previous_partners` to both `couple_card` calls in `subtree_children`**

In the `subtree_children` component, there are two branches that render boundary children with `couple_card`. Add the `previous_partners` prop to both.

**Branch 1 — `has_more` (around line 294):** Change from:

```elixir
<.couple_card
  person_a={child.person}
  person_b={child[:partner]}
  family_id={@family_id}
  organization={@organization}
  focused_person_id={@focused_person_id}
/>
```

To:

```elixir
<.couple_card
  person_a={child.person}
  person_b={child[:partner]}
  previous_partners={child[:previous_partners] || []}
  family_id={@family_id}
  organization={@organization}
  focused_person_id={@focused_person_id}
/>
```

**Branch 2 — fallback `true` (around line 316):** Same change — add `previous_partners={child[:previous_partners] || []}`.

- [ ] **Step 2: Start the dev server and verify visually**

Run: `iex -S mix phx.server`

Navigate to the family tree view with Nora Ashford as focus person. Verify:
- Humphrey shows Greta as his main partner (right side of couple card)
- Gilbert shows Greta as a previous partner (left side of couple card, via `previous_partners` rendering)
- Other siblings (Clifford + Ivy, Desmond + Mabel) are unaffected

- [ ] **Step 3: Run full test suite**

Run: `mix test`

Expected: All tests pass.

- [ ] **Step 4: Run precommit**

Run: `mix precommit`

Expected: Compiles without warnings, formatting clean, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "Pass previous_partners to couple_card for boundary children

The couple_card component already supports rendering previous_partners
but the subtree_children template never passed the data for at_limit
nodes. Now both the has_more and fallback branches include it."
```
