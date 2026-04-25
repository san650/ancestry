# Family Live

## Tree data

`PersonTree` (in `lib/ancestry/people/person_tree.ex`) walks `FamilyGraph` to produce a nested tree structure (person → partners → children). It is shared by both the interactive tree view and the print page. Each entry includes `has_more_up`, `has_more_down`, and `duplicated` flags for UI indicators.

## Visual components

The visual rendering components are intentionally separate so they can evolve independently:

- `TreeComponent` — interactive tree view with styled cards, photos, focus states, navigation links, and expansion indicators
- `PrintTreeComponent` — print-optimized plain text rendering with minimal styling
- `GraphComponent` — CSS Grid + SVG connector graph view

## Pages

- **`show.ex` / `show.html.heex`** — Interactive family view with graph view (CSS Grid + SVG connectors) and tree view (indented outline). Toggle between them via segmented pill in toolbar. Both use `PersonGraph` and `PersonTree` respectively.
- **`print.ex` / `print.html.heex`** — Print-optimized indented list view. Uses `PersonTree` for data, `PrintTreeComponent` for rendering. Pure HTML text, no SVG, no JS (except `AutoPrint` to trigger print dialog).
