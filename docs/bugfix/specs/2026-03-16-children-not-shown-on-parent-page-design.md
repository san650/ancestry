# Children Not Shown on Parent's Show Page

## Bug

When a parent is added to a person, navigating to the parent's show page does not list the person as a child.

### Root Cause

`load_relationships/2` in `Web.PersonLive.Show` loads children through two separate paths, both of which can miss children:

1. **`partner_children`** — iterates over the person's partners/ex-partners and calls `get_children_of_pair/2` for each. Only finds children whose *other* parent is a linked partner/ex-partner.
2. **`solo_children`** — calls `get_solo_children/1`, which explicitly excludes children that have a second parent.

Children with two parents who are NOT linked as partners/ex-partners fall through both paths and are invisible.

### Steps to Reproduce

1. Create persons A, B, and C in a family
2. Add B as a parent of A
3. Add C as a parent of A
4. Navigate to B's show page — A is not listed as a child
5. Navigate to C's show page — A is not listed as a child

## Solution

Replace the multiple specialized child queries with a single comprehensive query. Group results in memory in the LiveView.

### Query Layer

Add `get_children_with_coparents/1` to `Ancestry.Relationships`:

```elixir
def get_children_with_coparents(person_id) do
  from(child in Person,
    join: r1 in Relationship,
    on: r1.person_b_id == child.id and r1.person_a_id == ^person_id and r1.type == "parent",
    left_join: r2 in Relationship,
    on: r2.person_b_id == child.id and r2.type == "parent" and r2.person_a_id != ^person_id,
    left_join: coparent in Person,
    on: coparent.id == r2.person_a_id,
    select: {child, coparent}
  )
  |> Repo.all()
end
```

Returns `[{child, coparent | nil}]` — every child of the person, with their other parent if one exists.

### Remove Replaced Calls

Remove the following calls from `load_relationships/2`:
- `get_children_of_pair/2` (the per-partner N+1 loop in the `Enum.map` over partners)
- `get_solo_children/1`

Note: `get_children/1` is not called in `load_relationships/2` — it is already unused there. The function definitions for all three can remain in the context module (they may be used elsewhere or in tests).

### Grouping in `load_relationships/2`

After fetching `partners`, `ex_partners`, and `children_with_coparents`:

1. Build a MapSet of partner/ex-partner person IDs
2. Group children into three buckets:
   - **Partner children**: co-parent ID is in the partner set. Attach to the corresponding `{partner, rel, children}` tuple.
   - **Unlinked co-parent children**: co-parent exists but is NOT in the partner set. Group as `[{coparent, [children]}]`.
   - **Solo children**: co-parent is `nil`. Flat list.

Assigns produced:
- `@partner_children` — `[{partner, rel, [child]}]` (same shape as before)
- `@coparent_children` — `[{coparent, [child]}]` (new)
- `@solo_children` — `[child]` (same shape as before)

### Template Changes

The "Spouses & Children" column in the show template gets a new section between partner groups and solo children:

```heex
<%= for {coparent, children} <- @coparent_children do %>
  <div class="rounded-xl border border-base-300 p-4 space-y-3">
    <p class="text-xs font-medium text-base-content/40 uppercase tracking-wide">
      Children with
    </p>
    <.link navigate={~p"/families/#{@family.id}/members/#{coparent.id}"}
           class="rounded-lg transition-colors hover:bg-base-200">
      <.person_card person={coparent} highlighted={false} />
    </.link>
    <%= for child <- children do %>
      <.link navigate={~p"/families/#{@family.id}/members/#{child.id}"}
             class="rounded-lg transition-colors hover:bg-base-200">
        <.person_card person={child} highlighted={false} />
      </.link>
    <% end %>
  </div>
<% end %>
```

The coparent_children section intentionally does not include an "Add Child" button (unlike partner groups). Adding children with an unlinked co-parent is an uncommon flow — users can use the existing "Add Child" solo button and then add the second parent separately.

### Testing

1. **Query test** — `get_children_with_coparents/1` returns `{child, coparent}` when both parents exist and `{child, nil}` when only one parent exists
2. **Bucket boundary test** — when parent B and co-parent C are linked as partners, child A (with both B and C as parents) must appear in `partner_children` under the B-C group and must NOT also appear in `coparent_children`
3. **Unlinked co-parent bucket test** — when parent B and co-parent C are NOT linked as partners, child A must appear in `coparent_children` grouped under the co-parent, not in `partner_children` or `solo_children`
4. **LiveView integration test** — add two unlinked parents to a child, visit each parent's page, assert the child is visible within the coparent section specifically (e.g., by checking for the "Children with" heading and the child's name within that DOM section)

### Files Modified

- `lib/ancestry/relationships.ex` — add `get_children_with_coparents/1`
- `lib/web/live/person_live/show.ex` — rewrite child-loading logic in `load_relationships/2`, add `@coparent_children` assign
- `lib/web/live/person_live/show.html.heex` — add coparent_children section
- `test/ancestry/relationships_test.exs` — test new query
- `test/web/live/person_live/show_test.exs` — test children visibility
