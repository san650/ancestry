# Family Live

## Print page

The family tree has a dedicated print page (`print.ex` + `print.html.heex`) that opens in a new tab with an indented list layout.

- `PrintTreeComponent` renders the tree as an indented hierarchy with vertical border lines — keep this component separate from `GraphComponent` (the interactive grid view)
- `PrintTree` (in `lib/ancestry/people/print_tree.ex`) walks the `FamilyGraph` to produce a nested tree structure — it does NOT use `PersonGraph` or grid coordinates
- Both the print page and show page use the same underlying `FamilyGraph` data — changes to family data loading apply to both automatically
- The printing page and the show page must be kept in sync conceptually — if new relationship types are added or the FamilyGraph API changes, both pages must be updated accordingly

## Pages

- **`show.ex` / `show.html.heex`** — Interactive family tree view with CSS grid, SVG connectors, photos, hover effects, depth controls, side panel, and navigation. Uses `PersonGraph` for grid coordinates and `GraphConnector` JS hook for SVG.
- **`print.ex` / `print.html.heex`** — Print-optimized indented list view. Uses `PrintTree` to walk `FamilyGraph` directly. Pure HTML text, no SVG, no JS (except `AutoPrint` to trigger print dialog). Always fits on paper.
