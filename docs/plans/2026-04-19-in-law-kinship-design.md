# In-Law Kinship Support — Design Spec

## Goal

When two people in the kinship calculator have no common ancestor but ARE connected through a partner relationship (marriage or partnership), detect and display the in-law relationship instead of "No common ancestor found."

**Example:** Carlos García → (child of) → María López → (sibling of) → Pedro López → (partner of) → Ana Torres. Carlos is Ana's "Sobrino político" (nephew-in-law).

## Scope

- **Direct in-laws only** — single partner hop. No chained in-laws (concuñado/consuegro).
- **All partner types included** — married, relationship, divorced, separated. A divorced father-in-law is still a father-in-law.
- **Blood takes precedence** — if blood BFS finds an MRCA, never check in-law. In-law is a fallback only.
- **URL sharing (bundled fix)** — push both person IDs to query params so URLs are shareable. This completes existing half-wired `handle_params` — the read side already works, only `push_patch` is missing.

## Terminology — GENEALOGY.md Update

Already applied to `GENEALOGY.md`. See the "In-Laws — Familia Política" section.

### Rules

1. `político/a` always goes at the **end** of compound terms (this rule applies to extended in-law terms; the three core special terms — Suegro/a, Yerno/Nuera, Cuñado/a — use their own words instead of "político/a")
2. All gendered components inflect together (Tío abuelo político / Tía abuela política). For unknown gender, all components are slashed (Tío/a abuelo/a político/a)
3. Three relationships have **special terms**: Suegro/a, Yerno/Nuera, Cuñado/a
4. The in-law label describes "what person A is to person B" — gendered by **person A's gender**

### Core In-Law Terms (special words)

| Relationship | English (m) | English (f) | English (unknown) | Spanish (m) | Spanish (f) | Spanish (unknown) |
|---|---|---|---|---|---|---|
| Spouse | Husband | Wife | Spouse | Esposo | Esposa | Cónyuge |
| Parent-in-law | Father-in-law | Mother-in-law | Parent-in-law | Suegro | Suegra | Suegro/a |
| Child-in-law | Son-in-law | Daughter-in-law | Child-in-law | Yerno | Nuera | Yerno/Nuera |
| Sibling-in-law | Brother-in-law | Sister-in-law | Sibling-in-law | Cuñado | Cuñada | Cuñado/a |

> Note: "Yerno" and "Nuera" are distinct words, not gendered forms of the same root. The unknown form lists both: "Yerno/Nuera".

### Extended In-Law Terms (blood label + "político/a")

| Relationship | English (m) | English (f) | English (unknown) | Spanish (m) | Spanish (f) | Spanish (unknown) |
|---|---|---|---|---|---|---|
| Grandparent-in-law | Grandfather-in-law | Grandmother-in-law | Grandparent-in-law | Abuelo político | Abuela política | Abuelo/a político/a |
| Grandchild-in-law | Grandson-in-law | Granddaughter-in-law | Grandchild-in-law | Nieto político | Nieta política | Nieto/a político/a |
| Uncle/Aunt-in-law | Uncle-in-law | Aunt-in-law | Uncle/Aunt-in-law | Tío político | Tía política | Tío/a político/a |
| Nephew/Niece-in-law | Nephew-in-law | Niece-in-law | Nephew/Niece-in-law | Sobrino político | Sobrina política | Sobrino/a político/a |
| Cousin-in-law | Cousin-in-law | Cousin-in-law | Cousin-in-law | Primo político | Prima política | Primo/a político/a |
| Great Uncle/Aunt-in-law | Great uncle-in-law | Great aunt-in-law | Great uncle/aunt-in-law | Tío abuelo político | Tía abuela política | Tío/a abuelo/a político/a |
| Great Grand Uncle/Aunt-in-law | Great grand uncle-in-law | Great grand aunt-in-law | Great grand uncle/aunt-in-law | Tío bisabuelo político | Tía bisabuela política | Tío/a bisabuelo/a político/a |
| Grand Nephew/Niece-in-law | Grand nephew-in-law | Grand niece-in-law | Grand nephew/niece-in-law | Sobrino nieto político | Sobrina nieta política | Sobrino/a nieto/a político/a |
| Great Grand Nephew/Niece-in-law | Great grand nephew-in-law | Great grand niece-in-law | Great grand nephew/niece-in-law | Sobrino bisnieto político | Sobrina bisnieta política | Sobrino/a bisnieto/a político/a |
| Great Grandparent-in-law | Great grandfather-in-law | Great grandmother-in-law | Great grandparent-in-law | Bisabuelo político | Bisabuela política | Bisabuelo/a político/a |
| Great Great Grandparent-in-law | Great great grandfather-in-law | Great great grandmother-in-law | Great great grandparent-in-law | Tatarabuelo político | Tatarabuela política | Tatarabuelo/a político/a |
| Great Grandchild-in-law | Great grandson-in-law | Great granddaughter-in-law | Great grandchild-in-law | Bisnieto político | Bisnieta política | Bisnieto/a político/a |
| Great Great Grandchild-in-law | Great great grandson-in-law | Great great granddaughter-in-law | Great great grandchild-in-law | Tataranieto político | Tataranieta política | Tataranieto/a político/a |

**Formula:** For any extended in-law, construct the blood kinship label using **person A's gender**, then append `político` (m) / `política` (f) / `político/a` (unknown) at the end. Higher ordinals and removed cousins follow the same pattern (e.g., "Primo segundo político", "Tío abuelo tercero político").

## In-Law Label Construction — Delegation + Gettext

The in-law label module **delegates to `Kinship.Label`** for the blood component, then transforms the result. It does NOT duplicate `Label`'s classification logic.

### Approach

1. **Spouse** — handled before label: direct `pgettext(gender, "Spouse")` call, no coordinates involved
2. **Core special terms** `(0,1)`, `(1,0)`, `(1,1)` — use their own Gettext msgids (`"Parent-in-law"`, `"Child-in-law"`, `"Sibling-in-law"`) with gender-specific translations
3. **All other coordinates** — for English: construct the gendered English in-law form via Gettext (e.g., `"Uncle-in-law"`, `"Grandfather-in-law"`). For Spanish: call the existing Spanish label construction helpers (same as `Kinship.Label` uses internally) with person A's gender, then append `" político"` / `" política"` / `" político/a"`
4. **High ordinals** (≥6 generations, degree ≥3 cousins) — calculated with interpolation, same pattern as `Kinship.Label`

### Gettext msgids needed

Only the **core special terms** and the **named English in-law forms** need dedicated Gettext entries. Spanish extended in-laws are constructed programmatically (blood label + "político/a" suffix), matching how `Kinship.Label` already constructs Spanish labels programmatically for cousins and removed cousins.

**Core (4 msgids × 3 genders = 12 PO entries):**
- `"Spouse"`, `"Parent-in-law"`, `"Child-in-law"`, `"Sibling-in-law"`

**English named forms (need Gettext for gendered English):**
- `"Grandparent-in-law"`, `"Grandchild-in-law"`, `"Uncle/Aunt-in-law"`, `"Nephew/Niece-in-law"`, `"Cousin-in-law"`, `"Great Uncle/Aunt-in-law"`, `"Great Grand Uncle/Aunt-in-law"`, `"Grand Nephew/Niece-in-law"`, `"Great Grand Nephew/Niece-in-law"`, `"Great Grandparent-in-law"`, `"Great Great Grandparent-in-law"`, `"Great Grandchild-in-law"`, `"Great Great Grandchild-in-law"`, `"3rd Great Grandparent-in-law"`, `"3rd Great Grandchild-in-law"`

**Calculated (interpolation, no static PO entry):**
- `"%{nth} Great Grandparent-in-law"`, `"%{nth} Great Grandchild-in-law"`, `"%{nth} Great Grand Uncle/Aunt-in-law"`, `"%{nth} Great Grand Nephew/Niece-in-law"`, `"%{degree} Cousin-in-law"`, `"%{degree} Cousin, %{removed}-in-law"`

### Implementation: `InLaw.Label.format/3`

```elixir
def format(steps_a, steps_b, gender) do
  g = normalize_gender(gender)
  classify(steps_a, steps_b, g)
end

# Core special terms — own Gettext msgids
defp classify(0, 1, g), do: t(g, "Parent-in-law")
defp classify(1, 0, g), do: t(g, "Child-in-law")
defp classify(1, 1, g), do: t(g, "Sibling-in-law")

# Everything else — locale-aware construction
defp classify(steps_a, steps_b, g) do
  locale = Gettext.get_locale(Web.Gettext)
  if String.starts_with?(locale, "es") do
    # Construct blood label using Spanish helpers + append "político/a"
    blood = spanish_blood_label(steps_a, steps_b, g)
    "#{blood} #{politico_suffix(g)}"
  else
    english_in_law_label(steps_a, steps_b, g)
  end
end
```

The Spanish helpers (`spanish_base`, `spanish_generation_suffix`, `spanish_ordinal_suffix`) can be extracted from `Kinship.Label` as shared private functions, or the `InLaw.Label` module can call `Kinship.Label` internal helpers if they are made available. The simplest approach: extract these helpers into a shared `Kinship.Spanish` module or make them public on `Kinship.Label`.

## Algorithm — `Ancestry.Kinship.InLaw` Module

### Entry point: `InLaw.calculate(person_a_id, person_b_id)`

Called by the LiveView when `Kinship.calculate/2` returns `{:error, :no_common_ancestor}`.

### Steps

1. **Check direct spouse.** Query `Relationships.get_partner_relationship(a_id, b_id)`. If a partner relationship exists → return spouse result immediately. The spouse label uses `pgettext(gender, "Spouse")` with person A's gender — no coordinates involved.

2. **Partner-hop A side.** Get all partners of A (using all partner types via new `get_all_partners/1`). For each partner, run blood BFS: call `Kinship.build_ancestor_map/1` for both the partner and B, find MRCA, compute raw `(partner_steps, b_steps)`. **Coordinate mapping:** since A's partner stands in for A, the raw coordinates become `(steps_a=partner_steps, steps_b=b_steps)` — no transformation needed. Collect successful results with `side: :a`.

3. **Partner-hop B side.** Get all partners of B. For each partner, run blood BFS between A and that partner. Raw coordinates are `(a_steps, partner_steps)`. **Coordinate mapping:** since B's partner stands in for B, the raw coordinates become `(steps_a=a_steps, steps_b=partner_steps)` — no transformation needed. Collect successful results with `side: :b`.

4. **Pick best.** From all successful results, pick the one with the lowest `steps_a + steps_b`. Tiebreaker: prefer active partner type over former partner type.

5. **Construct label.** Using the mapped `(steps_a, steps_b)` and **person A's gender**, call `InLaw.Label.format/3`.

6. **Build path.** Construct a path with explicit partner annotation. Each node is `%{person: person, label: label, partner_link?: boolean}`. The two nodes forming the partner pair have `partner_link?: true`. The path is ordered: `[A, ..., partner_of_A_or_blood_relative, partner_link_person, ..., B]`.

### Return value

```elixir
# Direct spouse
{:ok, %Kinship.InLaw{
  relationship: "Esposa",
  partner_link: nil,                    # no bridge — they ARE the partners
  path: [%{person: a, label: "-", partner_link?: false},
         %{person: b, label: "-", partner_link?: false}]
}}

# In-law via partner hop
{:ok, %Kinship.InLaw{
  relationship: "Tía política",
  partner_link: %{person: %Person{},    # the partner who bridges
                  side: :a | :b},       # which person's partner
  path: [%{person: _, label: _, partner_link?: false}, ...]
}}

# No in-law relationship found either
{:error, :no_relationship}
```

The struct is intentionally minimal — no `steps_a`/`steps_b`, no `blood_relationship`, no `dna_percentage`. These are internal to label construction.

### BFS reuse

`Kinship.build_ancestor_map/1` (currently private) must be made public. It is a pure function with no side effects — safe to expose. The `InLaw` module calls it directly to avoid duplicating BFS logic.

### New context function

Add `Relationships.get_all_partners/1` (and `/2` with opts for optional family scoping) that returns all partner types in a single query, delegating to the existing private `get_relationship_partners/3` with `Relationship.partner_types()`. For in-law detection, partners should NOT be family-scoped — a partner could be in a different family.

## UI Changes

### LiveView (`KinshipLive`)

- **`maybe_calculate/1` refactor:** Remove `maybe_calculate()` from `select_person_a`/`select_person_b` event handlers. Instead, these handlers call `push_patch` with the updated `?person_a=ID&person_b=ID` params. The existing `handle_params` callback already calls `maybe_calculate()`, so the calculation happens exactly once via `handle_params`. This avoids double-calculation.
- **In-law fallback in `maybe_calculate/1`:** When `Kinship.calculate/2` returns `{:error, :no_common_ancestor}`, try `InLaw.calculate/2`. Store result as `{:ok, %Kinship{}}`, `{:ok, %Kinship.InLaw{}}`, or `{:error, atom}`.
- **Path assigns:** For `%Kinship.InLaw{}` results, set `@path_a` to the full path and `@path_b` to `[]` — the template renders it as a single linear column.

### Template

- **In-law result branch:** New `cond` branch matching `%Kinship.InLaw{}`
  - Shows relationship label (large, primary color)
  - Shows directional sentence: "A is B's tía política"
  - **No DNA percentage** (in-laws share no blood)
  - Shows "Parentesco por afinidad" / "Related by marriage" note
  - Linear path visualization (single column). Nodes with `partner_link?: true` are rendered with a heart/ring icon connector instead of an arrow
  
- **Updated error state:** When both blood and in-law fail, show "No relationship found" / "No se encontró parentesco" instead of "No common ancestor found"

### Path visualization for in-laws

Single-column linear path. The partner pair is distinguished by the connector between them:

```
[Person A]
    ↓
[Ancestor]
    ↓  
[A's uncle]
    ♥           ← partner connector (instead of arrow)
[Partner / Person related to B]
    ↓
[Person B]
```

Nodes with `partner_link?: true` get the partner connector between them. All other nodes get the standard arrow connector.

## Files to create/modify

| File | Action | Purpose |
|---|---|---|
| `lib/ancestry/kinship.ex` | Modify | Make `build_ancestor_map/1` public |
| `lib/ancestry/kinship/in_law.ex` | Create | In-law detection algorithm |
| `lib/ancestry/kinship/in_law_label.ex` | Create | In-law label construction (delegates to Label helpers) |
| `lib/ancestry/relationships.ex` | Modify | Add `get_all_partners/1` |
| `lib/web/live/kinship_live.ex` | Modify | Refactor to push_patch, in-law fallback |
| `lib/web/live/kinship_live.html.heex` | Modify | In-law result branch, updated error state |
| `priv/gettext/default.pot` | Modify | New in-law msgids |
| `priv/gettext/es-UY/LC_MESSAGES/default.po` | Modify | Spanish in-law translations |
| `priv/gettext/en-US/LC_MESSAGES/default.po` | Modify | English gendered in-law translations |
| `test/ancestry/kinship/in_law_test.exs` | Create | Unit tests for in-law algorithm |
| `test/ancestry/kinship/in_law_label_test.exs` | Create | Unit tests for in-law labels |
| `test/user_flows/kinship_in_law_test.exs` | Create | E2E tests per CLAUDE.md requirement |
| `test/user_flows/calculating_kinship_test.exs` | Modify | Update "no common ancestor" assertion to new error text |

## E2E Test Plan

Tests in `test/user_flows/kinship_in_law_test.exs` covering:

1. **Direct spouse** — select two partners, verify "Esposo/a" / "Husband/Wife" label
2. **Parent-in-law** — verify "Suegro/a" / "Father/Mother-in-law"
3. **Child-in-law (Yerno/Nuera)** — verify the inverse of parent-in-law uses distinct Yerno/Nuera terms, not gendered variants
4. **Sibling-in-law** — verify "Cuñado/a" / "Brother/Sister-in-law"
5. **Extended in-law** (uncle/aunt-in-law) — verify "Tío/a político/a" / "Uncle/Aunt-in-law"
6. **No relationship** — two people with no blood or in-law connection show "No relationship found"
7. **URL sharing** — selecting people updates URL params, loading URL pre-selects people and shows result
8. **Blood takes precedence** — two people with both blood and in-law paths show blood result
9. **Swap reverses in-law direction** — swapping A/B changes the label (e.g., "Father-in-law" ↔ "Son-in-law")
10. **Divorced partner still shows in-law** — a divorced couple's relatives still produce in-law results
