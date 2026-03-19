# Kinship MRCA Label & Arrow Connectors

## Problem

The MRCA node in the kinship tree shows only "Common Ancestor" with no kinship context. The connectors between nodes are plain lines with no directionality.

## Changes

### 1. MRCA kinship label

Show the MRCA node's existing relationship label (from Person A's perspective) above "(Common Ancestor)":

```
Grandparent
(Common Ancestor)
```

The data already exists — `mrca_node.label` contains the ascending label (e.g., "Grandparent"). Just render it in the template.

### 2. SVG arrow connectors

Replace CSS line connectors with small SVG arrows showing traversal direction:

- **Left branch (Person A → MRCA):** Arrows point UP
- **Right branch (MRCA → Person B):** Arrows point DOWN
- **Direct-line paths (single column):** Arrows point DOWN (top-to-bottom rendering)
- **Horizontal bar under MRCA:** Stays as CSS border (not directional)

SVG: 16x16, stroke-based, `text-base-300` color, `stroke-linecap: round`.

## Files to modify

- `lib/web/live/kinship_live.html.heex` — MRCA label + SVG arrows
- `lib/web/live/kinship_live.ex` — add arrow SVG function components
