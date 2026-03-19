# Family Metrics Design

## Overview

Add family metrics to the right sidebar of the family show page, displayed above the galleries list. Shows key statistics about the family at a glance.

## Metrics

### People Count & Photo Count

Two compact stat cards side by side. Icon, large number, subtle label below.

- **People count**: COUNT on family_members for the family
- **Photo count**: JOIN galleries -> photos WHERE gallery.family_id, COUNT

### Longest Descendant Line (Generations)

Vertical stack layout:

- Root ancestor mini card (clickable -> focuses tree)
- Dotted vertical line with "N generations" label in the middle
- Leaf descendant mini card (clickable -> focuses tree)

Calculation:
1. Find root ancestors: family members with no parents who are also family members
2. For each root, walk children recursively (scoped to family members only), tracking depth
3. Return longest chain's {count, root_person, leaf_person}
4. Count = number of people in the chain (not edges)
5. Returns nil if fewer than 2 people

Only shown when generations data is not nil.

### Oldest Person

Mini card with avatar/initials, name, and age. "Oldest Record" header.

Age calculation:
- If alive: current_year - birth_year (adjusted by month/day if available)
- If deceased with death_year: death_year - birth_year (adjusted)
- If deceased without death_year: skip, try next eligible person
- Only consider people with a birth_year

Clickable -> focuses that person in the tree. Shows "87 years" or "was 87 years" if deceased.

Only shown when an eligible person exists.

## Data Layer

New module: `Ancestry.Families.Metrics` at `lib/ancestry/families/metrics.ex`

Single entry point:

```elixir
Ancestry.Families.Metrics.compute(family_id)
# => %{
#   people_count: 23,
#   photo_count: 147,
#   generations: %{count: 4, root: %Person{}, leaf: %Person{}} | nil,
#   oldest_person: %{person: %Person{}, age: 87} | nil
# }
```

## UI Integration

### Side Panel

Metrics rendered inline in `SidePanelComponent` template, above `GalleryListComponent`. No separate LiveComponent needed — purely presentational markup driven by the `@metrics` map.

Layout order in side panel:
1. Metrics section (people + photos, generations, oldest)
2. Divider
3. Galleries
4. Divider
5. People

### Layout

- Desktop: metrics in right sidebar above galleries (side panel is right column)
- Mobile: side panel appears first naturally, so metrics are the first thing below the toolbar

### Mini Cards

All person mini cards are clickable using the existing `phx-click="focus_person"` event with `phx-value-id={person.id}`. Events bubble from LiveComponent to parent LiveView which already handles this.

Show person photo thumbnail if available, otherwise initials in a colored circle.

## LiveView Data Flow

### Mount

Call `Families.Metrics.compute(family_id)` in `mount/3`. Assign as `@metrics`. Pass to `SidePanelComponent`.

### Refreshing

Recompute metrics in existing callbacks that already reload related data:
- `link_person` / `relationship_saved` -> people count, generations may change
- Gallery created/deleted -> photo count may change
- No new PubSub subscriptions needed

### Empty State

Entire metrics section hidden if family has no people.

## Testing

### Unit Tests — `Ancestry.Families.Metrics`

- Empty family -> all zeroes/nils
- People but no photos -> photo_count: 0
- 3-generation chain -> generations.count == 3, correct root and leaf
- Multiple branches -> picks the longest
- Oldest person alive -> correct age from birth_year
- Oldest person deceased with death_year -> age at death
- Oldest person deceased without death_year -> skipped, next eligible picked
- Generations scoped to family members only

### User Flow Test — `test/user_flows/family_metrics_test.exs`

```
Given a family with several people, relationships, galleries with photos
When the user navigates to the family show page
Then the sidebar shows the people count and photo count
And the generations metric shows root and leaf person cards with the generation count
And the oldest person card is shown with their age

When the user clicks the oldest person card
Then the tree view loads that person

When the user clicks the root ancestor card in the generations metric
Then the tree view loads that person
```
