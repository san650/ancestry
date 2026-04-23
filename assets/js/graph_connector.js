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
    stroke: "rgba(11, 28, 48, 0.3)",
    strokeWidth: "2",
    strokeDasharray: null,
  },
  current_partner: {
    stroke: "rgba(74,222,128,0.6)",
    strokeWidth: "2",
    strokeDasharray: null,
  },
  previous_partner: {
    stroke: "rgba(11, 28, 48, 0.3)",
    strokeWidth: "2",
    strokeDasharray: null,
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
      // Reset all cell transforms before drawing to avoid accumulating shifts
      const grid = this._grid()
      if (grid) {
        grid.querySelectorAll('[data-node-id]').forEach(el => {
          el.style.transform = ''
        })
      }

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

      // Glue current partners first so rects are correct for connector drawing
      this._glueCouplePartners(coupleEdges)

      this._drawCoupleEdges(svg, coupleEdges)
      this._drawParentChildEdges(svg, parentChildEdges)
    })
  },

  // --- Couple connectors ---
  //
  // Horizontal line between adjacent partner cells.
  // Only draws for previous_partner (dashed). Current partners are glued together
  // visually via _glueCouplePartners and do not need a connecting line.

  _drawCoupleEdges(svg, edges) {
    for (const edge of edges) {
      // Fix 7: Skip drawing line for current_partner — they'll be glued together
      if (edge.type === "current_partner") continue

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

  // --- Fix 7: Glue current partners together ---
  //
  // For each current_partner edge, find both cells and translate them toward
  // each other by half the gap, eliminating the visual space between them.

  _glueCouplePartners(coupleEdges) {
    for (const edge of coupleEdges) {
      if (edge.type !== "current_partner") continue

      const grid = this._grid()
      if (!grid) continue
      const fromEl = grid.querySelector(`[data-node-id="${edge.from_id}"]`)
      const toEl = grid.querySelector(`[data-node-id="${edge.to_id}"]`)
      if (!fromEl || !toEl) continue

      // Measure the actual card elements (button inside the cell wrapper),
      // not the cell wrappers, to account for card width < cell width and borders
      const fromCard = fromEl.querySelector("button") || fromEl
      const toCard = toEl.querySelector("button") || toEl
      const fromRect = fromCard.getBoundingClientRect()
      const toRect = toCard.getBoundingClientRect()

      // Determine left and right elements
      const [leftEl, rightEl] = fromRect.left < toRect.left
        ? [fromEl, toEl] : [toEl, fromEl]
      const leftCard = leftEl.querySelector("button") || leftEl
      const rightCard = rightEl.querySelector("button") || rightEl
      const leftRect = leftCard.getBoundingClientRect()
      const rightRect = rightCard.getBoundingClientRect()

      // Gap = right card left edge - left card right edge (visual gap between cards)
      const gap = rightRect.left - leftRect.right
      if (gap <= 0) continue // already touching or overlapping

      const shift = gap / 2
      leftEl.style.transform = `translateX(${shift}px)`
      rightEl.style.transform = `translateX(-${shift}px)`
    }
  },

  // --- Parent → child connectors ---
  //
  // Fix 9: When both parents of a child are a current couple, merge their
  // parent-child groups into a single branch originating from the couple midpoint.
  //
  // For non-coupled parents (or solo parents), draw normally from the parent center.
  //
  // Groups with the same row gap are assigned different vertical lanes to prevent
  // visual merging.

  _drawParentChildEdges(svg, parentChildEdges) {
    if (parentChildEdges.length === 0) return

    // Parse all edges to find couple pairs and their type
    const allEdges = JSON.parse(this.el.dataset.edges)
    const couplePairs = new Map() // person_id -> { partnerId, type }
    for (const e of allEdges) {
      if (e.type === "current_partner" || e.type === "previous_partner") {
        couplePairs.set(e.from_id, { partnerId: e.to_id, coupleType: e.type })
        couplePairs.set(e.to_id, { partnerId: e.from_id, coupleType: e.type })
      }
    }

    // Group edges by child (to_id), then determine if both parents are a couple
    const byChild = new Map()
    for (const edge of parentChildEdges) {
      if (!byChild.has(edge.to_id)) byChild.set(edge.to_id, [])
      byChild.get(edge.to_id).push(edge)
    }

    // Build merged groups: if both parents of a child are a couple, merge into one
    // group with origin at the couple midpoint
    const mergedGroups = new Map() // groupKey -> { parentIds, children }

    for (const [childId, edges] of byChild) {
      if (edges.length === 2) {
        const [e1, e2] = edges
        // Check if these two parents are a couple
        const pair = couplePairs.get(e1.from_id)
        if (pair && pair.partnerId === e2.from_id) {
          // Couple! Use midpoint as origin
          const coupleKey = [e1.from_id, e2.from_id].sort().join(":")
          if (!mergedGroups.has(coupleKey)) {
            mergedGroups.set(coupleKey, { parentIds: [e1.from_id, e2.from_id], coupleType: pair.coupleType, children: [] })
          }
          mergedGroups.get(coupleKey).children.push({ edge: e1, childId })
          continue
        }
      }
      // Non-couple parents: each parent is its own group (existing behavior)
      for (const edge of edges) {
        const groupKey = `solo:${edge.from_id}`
        if (!mergedGroups.has(groupKey)) {
          mergedGroups.set(groupKey, { parentIds: [edge.from_id], children: [] })
        }
        mergedGroups.get(groupKey).children.push({ edge, childId })
      }
    }

    // Resolve rects for all groups
    const resolvedGroups = []
    for (const [key, group] of mergedGroups) {
      const { parentIds, children } = group

      // Compute origin X: midpoint between all parent cells
      const parentRects = parentIds.map(id => this._cellRect(id)).filter(Boolean)
      if (parentRects.length === 0) continue

      // Origin X = average center X of all parent rects
      const originX = parentRects.reduce((sum, r) => sum + this._centerX(r), 0) / parentRects.length

      // Origin Y: always start from bottom of parent cards so the horizontal
      // routing happens below the cards, never behind them.
      const originY = Math.max(...parentRects.map(r => this._bottom(r)))

      // For ex-partner couples, draw a vertical stub from the dashed couple
      // line down to the origin point, connecting the child branch to the
      // dashed partner line visually.
      const isMergedCouple = parentIds.length === 2 && !key.startsWith("solo:")
      const isExCouple = isMergedCouple && group.coupleType === "previous_partner"
      if (isExCouple) {
        const coupleLineY = Math.min(...parentRects.map(r => this._centerY(r)))
        const stubD = `M ${originX},${coupleLineY} V ${originY}`
        this._makePath(svg, stubD, { type: "previous_partner", relationship_kind: "parent" })
      }

      // Resolve child rects
      const resolvedChildren = []
      for (const { edge, childId } of children) {
        const toRect = this._cellRect(childId)
        if (!toRect) continue
        resolvedChildren.push({ edge, toRect })
      }
      if (resolvedChildren.length === 0) continue

      resolvedGroups.push({ originX, originY, children: resolvedChildren })
    }

    // Determine lane assignments within row-gap regions.
    //
    // Two groups share a row gap when their origin bottom y and first child top y
    // are in the same vertical band. We bucket groups by (approx originY, approx childTopY)
    // and assign sequential lane indices within each bucket.
    //
    // "Approximate" means snapped to the nearest 4px to tolerate sub-pixel differences.
    const snap = y => Math.round(y / 4) * 4

    const groupKey = (g) => {
      const parentBottom = snap(g.originY)
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
    const { originX, originY, children } = group

    // Origin: custom origin point (bottom center of parent cell, or couple midpoint)
    const ox = originX
    const oy = originY

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
