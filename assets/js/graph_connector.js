// assets/js/graph_connector.js
//
// GraphConnector — draws SVG connectors over a CSS Grid-based DAG layout.
//
// The hook element must have a `data-edges` attribute containing a JSON array
// of GraphEdge objects: { type, relationship_kind, from_id, to_id }.
//
// Cells are identified by `data-node-id` attributes on elements within
// the `[data-graph-grid]` element inside the hook root.

// --- Styling constants ---

const STYLES = {
  parent_child: {
    stroke: "rgba(128,128,128,0.4)",
    strokeWidth: "1.5",
    strokeDasharray: null,
  },
  current_partner: {
    stroke: "rgba(74,222,128,0.6)",
    strokeWidth: "2",
    strokeDasharray: null,
  },
  previous_partner: {
    stroke: "rgba(248,113,113,0.6)",
    strokeWidth: "2",
    strokeDasharray: "6",
  },
}

// Map relationship_kind → connector type for style lookup
function styleForEdge(edge) {
  switch (edge.type) {
    case "parent_child":
      return STYLES.parent_child
    case "current_partner":
      return STYLES.current_partner
    case "previous_partner":
      return STYLES.previous_partner
    default:
      return STYLES.parent_child
  }
}

const GraphConnector = {
  mounted() {
    this._svg = this._ensureSvg()
    this._observer = new ResizeObserver(() => this._draw())
    this._observer.observe(this.el)
    this._draw()
    this._scheduleScrollToFocus()
  },

  updated() {
    this._draw()
    this._scheduleScrollToFocus()
  },

  destroyed() {
    // Guard: mounted() may have short-circuited before setting _observer
    if (!this._observer) return
    this._observer.disconnect()
    const svg = this.el.querySelector("#graph-connector-svg")
    if (svg) svg.remove()
  },

  // --- SVG lifecycle ---

  _ensureSvg() {
    let svg = this.el.querySelector("#graph-connector-svg")
    if (!svg) {
      svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
      svg.id = "graph-connector-svg"
      svg.style.position = "absolute"
      svg.style.inset = "0"
      svg.style.pointerEvents = "none"
      svg.style.overflow = "visible"
      this.el.prepend(svg)
    }
    return svg
  },

  // --- Focus scrolling ---

  _scheduleScrollToFocus() {
    if (this._scrollTimer) clearTimeout(this._scrollTimer)
    this._scrollTimer = setTimeout(() => {
      const target = this.el.querySelector("[data-focus='true']")
      if (!target) return
      target.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })
    }, 50)
  },

  // --- Coordinate helpers ---

  // Convert a viewport-relative rect to SVG-local coordinates (accounts for scroll)
  _toLocal(rect) {
    const cr = this.el.getBoundingClientRect()
    return {
      left: rect.left - cr.left + this.el.scrollLeft,
      top: rect.top - cr.top + this.el.scrollTop,
      width: rect.width,
      height: rect.height,
    }
  },

  _centerX(local) {
    return local.left + local.width / 2
  },

  _centerY(local) {
    return local.top + local.height / 2
  },

  _bottom(local) {
    return local.top + local.height
  },

  // --- Grid helpers ---

  _grid() {
    return this.el.querySelector("[data-graph-grid]")
  },

  _cellRect(nodeId) {
    const grid = this._grid()
    if (!grid) return null
    const el = grid.querySelector(`[data-node-id="${nodeId}"]`)
    if (!el) return null
    return this._toLocal(el.getBoundingClientRect())
  },

  // --- Main draw ---

  _draw() {
    requestAnimationFrame(() => {
      const svg = this._ensureSvg()
      svg.replaceChildren()
      svg.setAttribute("width", this.el.scrollWidth)
      svg.setAttribute("height", this.el.scrollHeight)

      const edgesRaw = this.el.dataset.edges
      if (!edgesRaw) return
      let edges
      try {
        edges = JSON.parse(edgesRaw)
      } catch (_e) {
        return
      }
      if (!Array.isArray(edges) || edges.length === 0) return

      // Separate edges by type
      const parentChildEdges = edges.filter(e => e.type === "parent_child")
      const coupleEdges = edges.filter(e => e.type === "current_partner" || e.type === "previous_partner")

      this._drawCoupleEdges(svg, coupleEdges)
      this._drawParentChildEdges(svg, parentChildEdges)
    })
  },

  // --- Couple connectors ---
  //
  // Horizontal line between adjacent partner cells.
  // Solid for current partners, dashed for previous partners.

  _drawCoupleEdges(svg, edges) {
    for (const edge of edges) {
      const fromRect = this._cellRect(edge.from_id)
      const toRect = this._cellRect(edge.to_id)
      if (!fromRect || !toRect) continue

      const y = Math.min(this._centerY(fromRect), this._centerY(toRect))
      const x1 = this._centerX(fromRect)
      const x2 = this._centerX(toRect)

      const d = `M ${x1},${y} H ${x2}`
      this._makePath(svg, d, edge)
    }
  },

  // --- Parent → child connectors ---
  //
  // Groups edges by from_id (parent cell). Each group is drawn as:
  //   - One orthogonal branch from parent bottom → horizontal bar → drops to each child top
  //
  // When multiple groups share the same row gap (same parent row → same child row),
  // each group is assigned a different vertical lane (mid-y) to prevent visual merging.

  _drawParentChildEdges(svg, edges) {
    if (edges.length === 0) return

    // Group by from_id
    const groups = new Map()
    for (const edge of edges) {
      if (!groups.has(edge.from_id)) groups.set(edge.from_id, [])
      groups.get(edge.from_id).push(edge)
    }

    // Resolve rects for all from/to cells upfront
    const resolvedGroups = []
    for (const [fromId, groupEdges] of groups) {
      const fromRect = this._cellRect(fromId)
      if (!fromRect) continue

      const children = []
      for (const edge of groupEdges) {
        const toRect = this._cellRect(edge.to_id)
        if (!toRect) continue
        children.push({ edge, toRect })
      }
      if (children.length === 0) continue

      resolvedGroups.push({ fromId, fromRect, children })
    }

    // Determine lane assignments within row-gap regions.
    //
    // Two groups share a row gap when their parent bottom y and first child top y
    // are in the same vertical band. We bucket groups by (approx parentBottomY, approx childTopY)
    // and assign sequential lane indices within each bucket.
    //
    // "Approximate" means snapped to the nearest 4px to tolerate sub-pixel differences.
    const snap = y => Math.round(y / 4) * 4

    // Build a key from the group's vertical span
    const groupKey = (g) => {
      const parentBottom = snap(this._bottom(g.fromRect))
      const childTop = snap(g.children[0].toRect.top)
      return `${parentBottom}:${childTop}`
    }

    // Bucket groups by row-gap key
    const buckets = new Map()
    for (const g of resolvedGroups) {
      const key = groupKey(g)
      if (!buckets.has(key)) buckets.set(key, [])
      buckets.get(key).push(g)
    }

    // Draw each group with its lane offset
    for (const [_key, bucket] of buckets) {
      const laneCount = bucket.length
      for (let laneIdx = 0; laneIdx < laneCount; laneIdx++) {
        const g = bucket[laneIdx]
        this._drawParentChildGroup(svg, g, laneIdx, laneCount)
      }
    }
  },

  _drawParentChildGroup(svg, group, laneIdx, laneCount) {
    const { fromRect, children } = group

    // Origin: bottom center of parent cell
    const ox = this._centerX(fromRect)
    const oy = this._bottom(fromRect)

    // All children should have the same top y (same row in the grid).
    // Use the first child's top as the target y.
    const firstChildTop = children[0].toRect.top

    // Vertical gap between parent bottom and child top
    const gapHeight = firstChildTop - oy

    // Lane mid-y: divide gap into (laneCount + 1) slots
    const laneStep = gapHeight / (laneCount + 1)
    const midY = oy + laneStep * (laneIdx + 1)

    if (children.length === 1) {
      // Single child: simple orthogonal path, no horizontal bar needed
      const child = children[0]
      const cx = this._centerX(child.toRect)
      const cy = child.toRect.top

      const d = `M ${ox},${oy} V ${midY} H ${cx} V ${cy}`
      this._makePath(svg, d, child.edge)
    } else {
      // Multiple children: branch bar spanning all children
      //
      // Sort children left-to-right by center x
      const sorted = [...children].sort((a, b) => this._centerX(a.toRect) - this._centerX(b.toRect))

      const leftX = this._centerX(sorted[0].toRect)
      const rightX = this._centerX(sorted[sorted.length - 1].toRect)

      // Determine an appropriate representative edge for styling (use first child's edge)
      const repEdge = sorted[0].edge

      // Main branch: parent → midY, horizontal bar
      let d = `M ${ox},${oy} V ${midY} H ${leftX}`
      // Extend bar to the right
      d += ` M ${ox},${midY} H ${rightX}`

      this._makePath(svg, d, repEdge)

      // Vertical drops from bar to each child
      for (const child of sorted) {
        const cx = this._centerX(child.toRect)
        const cy = child.toRect.top
        const dropD = `M ${cx},${midY} V ${cy}`
        this._makePath(svg, dropD, child.edge)
      }
    }
  },

  // --- SVG element creation ---

  _makePath(svg, d, edge) {
    const p = document.createElementNS("http://www.w3.org/2000/svg", "path")
    p.setAttribute("d", d)
    p.setAttribute("fill", "none")
    p.setAttribute("stroke-linejoin", "round")
    p.setAttribute("stroke-linecap", "round")

    const style = styleForEdge(edge)
    p.setAttribute("stroke", style.stroke)
    p.setAttribute("stroke-width", style.strokeWidth)
    if (style.strokeDasharray) {
      p.setAttribute("stroke-dasharray", style.strokeDasharray)
    }

    // Data attribute for CSS targeting
    if (edge.relationship_kind) {
      p.setAttribute("data-relationship-kind", edge.relationship_kind)
    }

    svg.appendChild(p)
    return p
  },
}

export { GraphConnector }
