# Bug: Ex/former partners missing at depth boundary

## Problem

When the tree view renders children at the depth boundary (`at_limit = true`), only active partners (`married`, `relationship`) are shown. Former partners (`divorced`, `separated`) are completely ignored.

**Example:** Greta Whitfield married Gilbert Ashford (divorced 1975), then married Humphrey Ashford (1976). Both are children of Nora & Edgar Ashford. When Nora is the focus person, Humphrey shows Greta as his partner, but Gilbert appears alone — Greta should appear next to him as a previous partner.

## Root cause

`PersonGraph.build_child_units_acc/5` has two code paths:

1. **Full path** (`build_family_unit_full`) — queries active partners, former partners, and ex-partners separately, producing a rich data structure with `partner`, `previous_partners`, and `ex_partners` keys.
2. **Boundary path** (`at_limit = true`, lines 140-151) — only queries `FamilyGraph.active_partners/2`, producing `%{person: child, partner: partner, has_more: has_more, children: nil}`. Former partners are never fetched.

The template (`couple_card`) already supports rendering `previous_partners`, but boundary nodes never pass that data.

## Fix

### 1. Backend: `lib/ancestry/people/person_graph.ex` — `at_limit` branch (lines 140-151)

Replace the active-only partner query with `FamilyGraph.all_partners/2` (already exists at `family_graph.ex:106`). Sort all partners by marriage year descending, take the first as the main `partner`, put the rest into `previous_partners` as a flat list (no active/former distinction — at the boundary there are no children to group by partner, so the distinction adds no value).

**Before:**
```elixir
partners = FamilyGraph.active_partners(graph, child.id)

partner =
  case partners do
    [{p, _} | _] -> p
    [] -> nil
  end

{units ++ [%{person: child, partner: partner, has_more: has_more, children: nil}], vis}
```

**After:**
```elixir
all_partners = FamilyGraph.all_partners(graph, child.id)

sorted_partners =
  Enum.sort_by(all_partners, fn {p, rel} ->
    year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
    {year || 0, p.id}
  end, :desc)

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

### 2. Template: `lib/web/live/family_live/person_card_component.ex` — `subtree_children`

Pass `previous_partners` to `couple_card` in both boundary rendering branches (the `has_more` branch at line 294 and the fallback branch at line 316):

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

No changes to `couple_card` itself — it already accepts and renders `previous_partners`.

## Testing

Add a test in the existing `PersonGraph` test module that creates two siblings where one has an active partner and the other has a divorced partner who is the same person. Verify the boundary stub includes `previous_partners` for the sibling with the divorced relationship.
