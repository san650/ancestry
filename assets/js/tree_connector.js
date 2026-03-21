// assets/js/tree_connector.js

const STROKE = "rgba(128,128,128,0.2)"
const STROKE_WIDTH = "3"
const DASH_EX = "6,4"

const TreeConnector = {
  mounted() {
    this._svg = this._ensureSvg()
    this._ro = new ResizeObserver(() => this._draw())
    this._ro.observe(this.el)
    this.handleEvent("scroll_to_focus", () => this._scrollToFocus())
    this._scrollToFocus()
    this._draw()
  },

  updated() {
    this._draw()
  },

  destroyed() {
    if (this._ro) this._ro.disconnect()
    const svg = this.el.querySelector("#tree-connector-svg")
    if (svg) svg.remove()
  },

  _ensureSvg() {
    let svg = this.el.querySelector("#tree-connector-svg")
    if (!svg) {
      svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
      svg.id = "tree-connector-svg"
      svg.style.position = "absolute"
      svg.style.inset = "0"
      svg.style.pointerEvents = "none"
      svg.style.overflow = "visible"
      svg.style.zIndex = "-1"
      this.el.prepend(svg)
    }
    return svg
  },

  _scrollToFocus() {
    // 50ms delay lets the DOM settle after a LiveView patch
    setTimeout(() => {
      const target = this.el.querySelector("#focus-person-card")
      if (!target) return
      target.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })
    }, 50)
  },

  // Coordinate conversion: viewport rect → SVG-local coordinates
  _toLocal(rect) {
    const cr = this.el.getBoundingClientRect()
    return {
      left: rect.left - cr.left + this.el.scrollLeft,
      top: rect.top - cr.top + this.el.scrollTop,
      width: rect.width,
      height: rect.height,
    }
  },

  _centerX(rect) {
    const local = this._toLocal(rect)
    return local.left + local.width / 2
  },

  _draw() {
    requestAnimationFrame(() => {
      const svg = this._ensureSvg()
      svg.replaceChildren()
      svg.setAttribute("width", this.el.scrollWidth)
      svg.setAttribute("height", this.el.scrollHeight)

      this._drawBranchConnectors(svg)
      this._drawAncestorConnectors(svg)
      this._drawCoupleConnectors(svg)
      this._drawRootAncestorConnection(svg)
    })
  },

  _makePath(svg, d, dashed) {
    const p = document.createElementNS("http://www.w3.org/2000/svg", "path")
    p.setAttribute("d", d)
    p.setAttribute("fill", "none")
    p.setAttribute("stroke", STROKE)
    p.setAttribute("stroke-width", STROKE_WIDTH)
    p.setAttribute("stroke-linejoin", "round")
    p.setAttribute("stroke-linecap", "round")
    if (dashed) p.setAttribute("stroke-dasharray", DASH_EX)
    svg.appendChild(p)
  },

  // --- Branch connectors (couple → children) ---

  _drawBranchConnectors(svg) {
    const childrenRows = this.el.querySelectorAll("[data-children-row]")
    for (const row of childrenRows) {
      this._drawBranchForRow(svg, row)
    }
  },

  _drawBranchForRow(svg, row) {
    const columns = row.querySelectorAll(":scope > [data-child-column]")
    if (columns.length === 0) return

    const primaryCol = row.closest("[data-primary-column]")
    if (!primaryCol) return
    const coupleCard = primaryCol.querySelector(":scope > [data-couple-card]")
    if (!coupleCard) return

    // Group children by line origin
    const groups = {}

    for (const col of columns) {
      const origin = col.dataset.lineOrigin || "partner"
      if (!groups[origin]) groups[origin] = []
      const childId = col.dataset.childPersonId
      let cx
      if (childId) {
        const personEl = col.querySelector(`[data-person-id="${childId}"]`)
        if (personEl) cx = this._centerX(personEl.getBoundingClientRect())
      }
      if (cx === undefined) cx = this._centerX(col.getBoundingClientRect())
      groups[origin].push(cx)
    }

    // Sort groups into stacking order
    const sortedGroups = Object.entries(groups).sort((a, b) => {
      const aKey = a[0], bKey = b[0]
      const aOrder = aKey === "partner" ? 0 : aKey === "solo" ? 3 : aKey.startsWith("prev-") ? 1 : 2
      const bOrder = bKey === "partner" ? 0 : bKey === "solo" ? 3 : bKey.startsWith("prev-") ? 1 : 2
      return aOrder - bOrder
    })

    // Compute origin Y (bottom of couple card) and target Y (top of first child)
    const coupleRect = this._toLocal(coupleCard.getBoundingClientRect())
    const oy = coupleRect.top + coupleRect.height

    // Get target Y from first child column's top
    const firstCol = columns[0]
    const firstChildCard = firstCol.querySelector("[data-couple-card], [data-person-id]")
    const cy = firstChildCard
      ? this._toLocal(firstChildCard.getBoundingClientRect()).top
      : this._toLocal(firstCol.getBoundingClientRect()).top

    // Dynamic margin: set children row margin-top to create space for connector zone
    const numGroups = sortedGroups.length
    const gap = Math.max(20, 10 + numGroups * 10)
    row.style.marginTop = gap + "px"

    // Recompute cy after margin change
    const cyActual = firstChildCard
      ? this._toLocal(firstChildCard.getBoundingClientRect()).top
      : this._toLocal(firstCol.getBoundingClientRect()).top

    // Draw each group
    sortedGroups.forEach(([origin, centers], groupIndex) => {
      const barY = oy + 10 + groupIndex * 10
      const isDashed = origin.startsWith("ex-")
      const ox = this._getOriginX(origin, coupleCard)

      // Build path: M ox,oy V barY, then for each child H cx V cy
      let d = `M ${ox},${oy} V ${barY}`
      centers.forEach((cx, i) => {
        if (i === 0) {
          d += ` H ${cx} V ${cyActual}`
        } else {
          d += ` M ${ox},${barY} H ${cx} V ${cyActual}`
        }
      })
      this._makePath(svg, d, isDashed)
    })
  },

  _getOriginX(origin, coupleCard) {
    if (origin === "partner") {
      const aId = coupleCard.dataset.personAId
      const bId = coupleCard.dataset.personBId
      if (aId && bId) {
        const a = coupleCard.querySelector(`[data-person-id="${aId}"]`)
        const b = coupleCard.querySelector(`[data-person-id="${bId}"]`)
        if (a && b) {
          return (this._centerX(a.getBoundingClientRect()) + this._centerX(b.getBoundingClientRect())) / 2
        }
      }
      // Fallback: just person_a center
      const aId2 = coupleCard.dataset.personAId
      if (aId2) {
        const a = coupleCard.querySelector(`[data-person-id="${aId2}"]`)
        if (a) return this._centerX(a.getBoundingClientRect())
      }
    } else if (origin === "solo") {
      const aId = coupleCard.dataset.personAId
      if (aId) {
        const a = coupleCard.querySelector(`[data-person-id="${aId}"]`)
        if (a) return this._centerX(a.getBoundingClientRect())
      }
    } else if (origin.startsWith("ex-")) {
      const exId = origin.replace("ex-", "")
      const sep = coupleCard.querySelector(`[data-ex-separator="${exId}"]`)
      if (sep) return this._centerX(sep.getBoundingClientRect())
    } else if (origin.startsWith("prev-")) {
      const prevId = origin.replace("prev-", "")
      const sep = coupleCard.querySelector(`[data-previous-separator="${prevId}"]`)
      if (sep) return this._centerX(sep.getBoundingClientRect())
    }
    // Fallback
    const cr = this._toLocal(coupleCard.getBoundingClientRect())
    return cr.left + cr.width / 2
  },

  // --- Ancestor connectors (parents above → couple below) ---

  _drawAncestorConnectors(svg) {
    const ancestorRows = this.el.querySelectorAll("[data-ancestor-parents-row]")
    for (const row of ancestorRows) {
      this._drawAncestorForRow(svg, row)
    }
  },

  _drawAncestorForRow(svg, row) {
    const parentColumns = row.querySelectorAll(":scope > [data-ancestor-parent-column]")
    if (parentColumns.length === 0) return

    const container = row.parentElement
    if (!container) return
    const coupleCardBelow = container.querySelector(":scope > [data-couple-card]")
    if (!coupleCardBelow) return

    for (const col of parentColumns) {
      const subtreeRoot = col.children[0]
      const bottomCouple = subtreeRoot?.querySelector(":scope > [data-couple-card]")
      const sourceEl = bottomCouple || col
      const sourceRect = this._toLocal(sourceEl.getBoundingClientRect())
      const px = sourceRect.left + sourceRect.width / 2
      const py = sourceRect.top + sourceRect.height

      const targetId = col.dataset.targetPersonId
      let cx, cy
      if (targetId) {
        const personEl = coupleCardBelow.querySelector(`[data-person-id="${targetId}"]`)
        if (personEl) {
          const pRect = this._toLocal(personEl.getBoundingClientRect())
          cx = pRect.left + pRect.width / 2
          cy = pRect.top
        }
      }
      if (cx === undefined) {
        const ccRect = this._toLocal(coupleCardBelow.getBoundingClientRect())
        cx = ccRect.left + ccRect.width / 2
        cy = ccRect.top
      }

      const barY = py + (cy - py) / 2
      const d = `M ${px},${py} V ${barY} H ${cx} V ${cy}`
      this._makePath(svg, d, false)
    }
  },

  // --- Couple-level connectors (ex/previous partner horizontal links) ---

  _drawCoupleConnectors(svg) {
    const coupleCards = this.el.querySelectorAll("[data-couple-card]")
    for (const card of coupleCards) {
      this._drawCoupleLinks(svg, card)
    }
  },

  _drawCoupleLinks(svg, card) {
    const exSeps = card.querySelectorAll("[data-ex-separator]")
    for (const sep of exSeps) {
      this._drawPartnerLink(svg, sep, card, true)
    }
    const prevSeps = card.querySelectorAll("[data-previous-separator]")
    for (const sep of prevSeps) {
      this._drawPartnerLink(svg, sep, card, false)
    }
  },

  _drawPartnerLink(svg, separator, coupleCard, isDashed) {
    const sepRect = this._toLocal(separator.getBoundingClientRect())
    const cardRect = this._toLocal(coupleCard.getBoundingClientRect())

    const personCard = separator.previousElementSibling
    if (!personCard) return
    const personRect = this._toLocal(personCard.getBoundingClientRect())

    const aId = coupleCard.dataset.personAId
    let mainPersonRect
    if (aId) {
      const mainPerson = coupleCard.querySelector(`[data-person-id="${aId}"]`)
      if (mainPerson) mainPersonRect = this._toLocal(mainPerson.getBoundingClientRect())
    }

    const y = cardRect.top + cardRect.height / 2
    const x1 = personRect.left + personRect.width / 2
    const x2 = mainPersonRect
      ? mainPersonRect.left + mainPersonRect.width / 2
      : sepRect.left + sepRect.width

    let d = `M ${x1},${y} H ${x2}`

    const sepId = separator.dataset.exSeparator || separator.dataset.previousSeparator
    const prefix = separator.dataset.exSeparator ? "ex-" : "prev-"
    const origin = prefix + sepId
    const hasChildren = this.el.querySelector(`[data-line-origin="${origin}"]`)
    if (hasChildren) {
      const sepCx = sepRect.left + sepRect.width / 2
      const dropY = cardRect.top + cardRect.height
      d += ` M ${sepCx},${y} V ${dropY}`
    }

    this._makePath(svg, d, isDashed)
  },

  // --- Root ancestor → focus person connection ---
  // Connects the parents' couple card (bottom of ancestor subtree) to the focus person
  // card in the center row. This handles the top-level gap that the recursive
  // ancestor_subtree connectors don't cover.

  _drawRootAncestorConnection(svg) {
    const focusPerson = this.el.querySelector("#focus-person-card")
    if (!focusPerson) return

    // The focus person is inside a couple card in a [data-primary-column]
    const centerCoupleCard = focusPerson.closest("[data-couple-card]")
    if (!centerCoupleCard) return

    // Find the ancestor couple card: the closest [data-couple-card] that is NOT
    // inside a [data-primary-column] and is positioned above the center couple card.
    // This is the parents' couple card at the bottom of the ancestor subtree.
    const allCoupleCards = this.el.querySelectorAll("[data-couple-card]")
    const centerRect = this._toLocal(centerCoupleCard.getBoundingClientRect())

    let parentsCoupleCard = null
    let closestDistance = Infinity

    for (const card of allCoupleCards) {
      // Skip cards inside data-primary-column (those are center/descendant couple cards)
      if (card.closest("[data-primary-column]")) continue
      // Skip the card if it's the same as center (shouldn't happen, but guard)
      if (card === centerCoupleCard) continue

      const cardRect = this._toLocal(card.getBoundingClientRect())
      const cardBottom = cardRect.top + cardRect.height

      // Must be above the center couple card
      if (cardBottom > centerRect.top) continue

      // Find the closest one (smallest gap)
      const distance = centerRect.top - cardBottom
      if (distance < closestDistance) {
        closestDistance = distance
        parentsCoupleCard = card
      }
    }

    if (!parentsCoupleCard) return

    // Draw path from parents couple card bottom center → focus person top center
    const parentsRect = this._toLocal(parentsCoupleCard.getBoundingClientRect())
    const px = parentsRect.left + parentsRect.width / 2
    const py = parentsRect.top + parentsRect.height

    const focusRect = this._toLocal(focusPerson.getBoundingClientRect())
    const cx = focusRect.left + focusRect.width / 2
    const cy = focusRect.top

    const barY = py + (cy - py) / 2
    const d = `M ${px},${py} V ${barY} H ${cx} V ${cy}`
    this._makePath(svg, d, false)
  },
}

export { TreeConnector }
