# Family Live

## Print page

The family tree has a dedicated print page (`print.ex` + `print.html.heex`) that opens in a new tab.

- `PrintGraphComponent` renders the tree with simplified text-only person cards — keep this component separate from `GraphComponent` so each can evolve independently
- Both components consume the same `PersonGraph` struct — changes to graph computation apply to both views automatically
- Both use the `GraphConnector` JS hook for SVG connectors
- The printing page and the show page must be kept in sync when graph rendering changes — if you modify how nodes are positioned in the grid, edges are structured, or the `PersonGraph` API, both pages must be updated accordingly

## Pages

- **`show.ex` / `show.html.heex`** — Interactive family tree view with photos, hover effects, depth controls, side panel, and navigation. This is the main page users interact with.
- **`print.ex` / `print.html.heex`** — Print-optimized view with text-only person cards. Opens in a new tab and auto-triggers the browser print dialog. No interactive chrome.
