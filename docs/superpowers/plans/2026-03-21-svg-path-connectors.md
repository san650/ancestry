# SVG Path Connectors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-`<line>` SVG connector system with single `<path>` elements drawn by a unified `TreeConnector` JS hook, reducing DOM elements and solving horizontal bar overlap.

**Architecture:** A single `TreeConnector` hook on `#tree-canvas` replaces `BranchConnector`, `AncestorConnector`, `ScrollToFocus`, and inline couple-card SVGs. It injects one absolute-positioned SVG overlay and draws all connections as `<path>` elements using DOM position measurements.

**Tech Stack:** Phoenix LiveView, JavaScript (LiveView hooks), SVG paths, Tailwind CSS

**Spec:** `docs/superpowers/specs/2026-03-21-svg-path-connectors-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `assets/js/tree_connector.js` | Create | TreeConnector hook: SVG overlay, path drawing, scroll-to-focus |
| `assets/js/app.js` | Modify | Remove old hooks, import TreeConnector |
| `lib/web/live/family_live/person_card_component.ex` | Modify | Remove inline SVGs, replace with spacer divs, remove connector divs |
| `lib/web/live/family_live/show.html.heex` | Modify | Replace ScrollToFocus hook with TreeConnector, add `relative` |
| `test/web/live/family_live/tree_connector_dom_test.exs` | Create | DOM structure tests for the refactored templates |

---

### Task 1: Create TreeConnector hook with SVG overlay and ScrollToFocus

**Files:**
- Create: `assets/js/tree_connector.js`

This task creates the hook skeleton with SVG injection, ResizeObserver, and the absorbed ScrollToFocus logic. No drawing yet — just the lifecycle and overlay.

- [ ] **Step 1: Create `tree_connector.js` with hook skeleton**

```js
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
      this.el.appendChild(svg)
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
    // Find all children rows in the tree
    const childrenRows = this.el.querySelectorAll("[data-children-row]")
    for (const row of childrenRows) {
      this._drawBranchForRow(svg, row)
    }
  },

  _drawBranchForRow(svg, row) {
    const columns = row.querySelectorAll(":scope > [data-child-column]")
    if (columns.length === 0) return

    // The couple card is the previous sibling of the children row's parent
    // Structure: [data-primary-column] > couple_card + (wrapper > [data-children-row])
    // OR: [data-primary-column] > couple_card + [data-children-row]
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

    // The couple card below is the next sibling of this parents row's parent wrapper
    // Structure: [flex-col] > [ancestor-parents-row] + [couple-card]
    const container = row.parentElement
    if (!container) return
    const coupleCardBelow = container.querySelector(":scope > [data-couple-card]")
    if (!coupleCardBelow) return

    for (const col of parentColumns) {
      // Source: bottom couple card in the parent column
      const subtreeRoot = col.children[0]
      const bottomCouple = subtreeRoot?.querySelector(":scope > [data-couple-card]")
      const sourceEl = bottomCouple || col
      const sourceRect = this._toLocal(sourceEl.getBoundingClientRect())
      const px = sourceRect.left + sourceRect.width / 2
      const py = sourceRect.top + sourceRect.height

      // Target: specific person in the couple card below
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

      // barY = midpoint between parent bottom and child top
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
    // Find ex-partner separators
    const exSeps = card.querySelectorAll("[data-ex-separator]")
    for (const sep of exSeps) {
      this._drawPartnerLink(svg, sep, card, true)
    }
    // Find previous-partner separators
    const prevSeps = card.querySelectorAll("[data-previous-separator]")
    for (const sep of prevSeps) {
      this._drawPartnerLink(svg, sep, card, false)
    }
  },

  _drawPartnerLink(svg, separator, coupleCard, isDashed) {
    // The separator sits between the ex/previous person card (to its left) and the main couple (to its right)
    // Draw a horizontal line at the couple card's vertical midpoint through the separator
    const sepRect = this._toLocal(separator.getBoundingClientRect())
    const cardRect = this._toLocal(coupleCard.getBoundingClientRect())

    // The person card is the previous sibling of the separator
    const personCard = separator.previousElementSibling
    if (!personCard) return
    const personRect = this._toLocal(personCard.getBoundingClientRect())

    // Find the main couple's leftmost person card (person_a)
    const aId = coupleCard.dataset.personAId
    let mainPersonRect
    if (aId) {
      const mainPerson = coupleCard.querySelector(`[data-person-id="${aId}"]`)
      if (mainPerson) mainPersonRect = this._toLocal(mainPerson.getBoundingClientRect())
    }

    // Horizontal line from ex person center to main person center (or separator right edge)
    const y = cardRect.top + cardRect.height / 2
    const x1 = personRect.left + personRect.width / 2
    const x2 = mainPersonRect
      ? mainPersonRect.left + mainPersonRect.width / 2
      : sepRect.left + sepRect.width

    let d = `M ${x1},${y} H ${x2}`

    // If this separator has children, draw a vertical drop from the separator midpoint
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
}

export { TreeConnector }
```

- [ ] **Step 2: Verify file was created**

Run: `ls -la assets/js/tree_connector.js`
Expected: File exists.

- [ ] **Step 3: Commit**

```bash
git add assets/js/tree_connector.js
git commit -m "Add TreeConnector hook with SVG overlay and path drawing"
```

---

### Task 2: Wire TreeConnector into app.js, remove old hooks

**Files:**
- Modify: `assets/js/app.js:52-261`

- [ ] **Step 1: Remove old hooks and add TreeConnector import**

In `assets/js/app.js`:

1. Add import at top (after line 27):
```js
import { TreeConnector } from "./tree_connector"
```

2. Remove `makeSvgLine` function (lines 52-59)

3. Remove `CONNECTOR_STROKE` constant (line 61)

4. Remove `BranchConnector` hook (lines 63-176)

5. Remove `AncestorConnector` hook (lines 180-235)

6. Remove `ScrollToFocus` hook (lines 238-255)

7. Update hooks object (line 261) from:
```js
hooks: { ...colocatedHooks, FuzzyFilter, BranchConnector, AncestorConnector, ScrollToFocus, PhotoTagger, PersonHighlight },
```
to:
```js
hooks: { ...colocatedHooks, FuzzyFilter, TreeConnector, PhotoTagger, PersonHighlight },
```

- [ ] **Step 2: Verify JS compiles**

Run: `cd /Users/babbage/Work/family && mix assets.build 2>&1 | tail -5`
Expected: No errors. If using esbuild, it should complete without import errors.

- [ ] **Step 3: Commit**

```bash
git add assets/js/app.js
git commit -m "Wire TreeConnector hook, remove BranchConnector/AncestorConnector/ScrollToFocus"
```

---

### Task 3: Update `show.html.heex` — replace ScrollToFocus with TreeConnector

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex:73-87`

- [ ] **Step 1: Replace hook and add `relative` class on `#tree-canvas`**

Change line 73-77 from:
```html
    <div
      id="tree-canvas"
      class="overflow-x-auto p-6 order-last lg:order-first"
      phx-hook="ScrollToFocus"
    >
```
to:
```html
    <div
      id="tree-canvas"
      class="relative overflow-x-auto p-6 order-last lg:order-first"
      phx-hook="TreeConnector"
    >
```

- [ ] **Step 2: Remove the `vline` between ancestors and center row**

Remove line 87 ONLY:
```html
            <.vline height={24} />
```

The TreeConnector hook now draws the ancestor-to-center connection. **Important:** Do NOT remove the other `<.vline>` calls at lines 95 and 281 — those are placeholder connectors for add-parent and add-child, which are static and must be preserved.

- [ ] **Step 3: Verify template compiles**

Run: `cd /Users/babbage/Work/family && mix compile --no-optional-deps 2>&1 | tail -5`
Expected: No compilation errors.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/show.html.heex
git commit -m "Replace ScrollToFocus with TreeConnector hook on tree canvas"
```

---

### Task 4: Update `couple_card/1` — replace inline SVGs with spacer divs

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex:115-186`

- [ ] **Step 1: Replace ex-partner inline SVGs with spacer divs**

Replace lines 115-151 (the ex-partners loop) from:
```elixir
      <%!-- Ex-partners on the sides (dashed lines) --%>
      <%= for ex_group <- @ex_partners do %>
        <.person_card
          person={ex_group.person}
          family_id={@family_id}
          focused={false}
        />
        <svg
          data-ex-separator={ex_group.person.id}
          class="w-2 h-1"
          viewBox="0 0 40 123"
          style="width: 40px; height: 123px;"
        >
          <line
            x1="0"
            y1="55"
            x2="40"
            y2="55"
            stroke="rgba(128,128,128,0.2)"
            stroke-width="3"
            stroke-dasharray="5"
          >
          </line>
          <%= if ex_group.children != [] do %>
            <line
              x1="20"
              y1="55"
              x2="20"
              y2="123"
              stroke="rgba(128,128,128,0.2)"
              stroke-width="3"
              stroke-dasharray="5"
            >
            </line>
          <% end %>
        </svg>
      <% end %>
```

to:
```elixir
      <%!-- Ex-partners on the sides --%>
      <%= for ex_group <- @ex_partners do %>
        <.person_card
          person={ex_group.person}
          family_id={@family_id}
          focused={false}
        />
        <div data-ex-separator={ex_group.person.id} class="w-[40px] self-stretch"></div>
      <% end %>
```

- [ ] **Step 2: Replace previous-partner inline SVGs with spacer divs**

Replace lines 152-186 (the previous-partners loop) from:
```elixir
      <%!-- Previous partners on the sides (solid lines) --%>
      <%= for prev_group <- @previous_partners do %>
        <.person_card
          person={prev_group.person}
          family_id={@family_id}
          focused={false}
        />
        <svg
          data-previous-separator={prev_group.person.id}
          class="w-2 h-1"
          viewBox="0 0 40 123"
          style="width: 40px; height: 123px;"
        >
          <line
            x1="0"
            y1="55"
            x2="40"
            y2="55"
            stroke="rgba(128,128,128,0.2)"
            stroke-width="3"
          >
          </line>
          <%= if prev_group.children != [] do %>
            <line
              x1="20"
              y1="55"
              x2="20"
              y2="123"
              stroke="rgba(128,128,128,0.2)"
              stroke-width="3"
            >
            </line>
          <% end %>
        </svg>
      <% end %>
```

to:
```elixir
      <%!-- Previous partners on the sides --%>
      <%= for prev_group <- @previous_partners do %>
        <.person_card
          person={prev_group.person}
          family_id={@family_id}
          focused={false}
        />
        <div data-previous-separator={prev_group.person.id} class="w-[40px] self-stretch"></div>
      <% end %>
```

- [ ] **Step 3: Verify template compiles**

Run: `cd /Users/babbage/Work/family && mix compile --no-optional-deps 2>&1 | tail -5`
Expected: No compilation errors.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "Replace couple card inline SVGs with spacer divs"
```

---

### Task 5: Remove BranchConnector and AncestorConnector divs from templates

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex:295-395`

- [ ] **Step 1: Remove the BranchConnector div from `subtree_children/1`**

In the `subtree_children/1` function, remove the `connector_id` assign (line 296) and the connector div (lines 300-309).

Change the function from:
```elixir
  def subtree_children(assigns) do
    assigns = assign(assigns, :connector_id, "conn-#{System.unique_integer([:positive])}")

    ~H"""
    <div class="flex flex-col items-center">
      <%!-- SVG connector drawn by JS hook --%>
      <div
        id={@connector_id}
        phx-hook="BranchConnector"
        phx-update="ignore"
        class="w-full"
        style="height: 20px; position: relative;"
      >
        <svg class="absolute inset-0 w-full h-full overflow-visible"></svg>
      </div>
      <div class="flex items-start gap-6" data-children-row>
```

to:
```elixir
  def subtree_children(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <div class="flex items-start gap-6" data-children-row>
```

The remainder of the function body (the `<%= for child <- @children do %>` loop, closing tags, `"""`, and `end`) is unchanged — keep it exactly as-is.

- [ ] **Step 2: Remove the AncestorConnector div from `ancestor_subtree/1`**

Remove the `connector_id` assign (line 361) and the connector div (lines 377-385).

Change:
```elixir
  def ancestor_subtree(assigns) do
    assigns = assign(assigns, :connector_id, "anc-#{System.unique_integer([:positive])}")

    ~H"""
    <div class="flex flex-col items-center">
      <%= if @node.parent_trees != [] do %>
        <div class="flex items-end justify-center gap-8" data-ancestor-parents-row>
          <%= for entry <- @node.parent_trees do %>
            <div data-ancestor-parent-column data-target-person-id={entry.for_person_id}>
              <.ancestor_subtree
                node={entry.tree}
                family_id={@family_id}
                focused_person_id={@focused_person_id}
              />
            </div>
          <% end %>
        </div>
        <div
          id={@connector_id}
          phx-hook="AncestorConnector"
          phx-update="ignore"
          class="w-full"
          style="height: 20px; position: relative;"
        >
          <svg class="absolute inset-0 w-full h-full overflow-visible"></svg>
        </div>
      <% end %>
```

to (complete function):
```elixir
  def ancestor_subtree(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <%= if @node.parent_trees != [] do %>
        <div class="flex items-end justify-center gap-8 mb-5" data-ancestor-parents-row>
          <%= for entry <- @node.parent_trees do %>
            <div data-ancestor-parent-column data-target-person-id={entry.for_person_id}>
              <.ancestor_subtree
                node={entry.tree}
                family_id={@family_id}
                focused_person_id={@focused_person_id}
              />
            </div>
          <% end %>
        </div>
      <% end %>
      <.couple_card
        person_a={@node.couple.person_a}
        person_b={@node.couple.person_b}
        family_id={@family_id}
        focused_person_id={@focused_person_id}
      />
    </div>
    """
  end
```

Note: `mb-5` (20px) added to the ancestor parents row to create space for the ancestor connector paths (replacing the removed 20px-height div). The couple card render and closing tags are unchanged from the original.

- [ ] **Step 3: Verify template compiles**

Run: `cd /Users/babbage/Work/family && mix compile --no-optional-deps 2>&1 | tail -5`
Expected: No compilation errors.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "Remove BranchConnector and AncestorConnector divs from templates"
```

---

### Task 6: Run existing tests to verify no regressions

**Files:**
- Test: `test/web/live/family_live/tree_multiple_partners_test.exs`

- [ ] **Step 1: Run the existing partner tree tests**

Run: `cd /Users/babbage/Work/family && mix test test/web/live/family_live/tree_multiple_partners_test.exs --trace`

Expected: All 4 tests pass. The `data-previous-separator` and `data-ex-separator` attributes are still present on the replacement spacer divs.

- [ ] **Step 2: Run all tests to catch regressions**

Run: `cd /Users/babbage/Work/family && mix test`

Expected: All tests pass. The template changes preserve all data attributes that existing tests assert on.

- [ ] **Step 3: Fix any failures**

If tests fail, check:
- `data-ex-separator` / `data-previous-separator` attributes are on the spacer divs
- `data-couple-card`, `data-person-a-id`, `data-person-b-id` unchanged
- `data-child-column`, `data-line-origin` unchanged
- No references to `BranchConnector`, `AncestorConnector`, or `ScrollToFocus` in test assertions

---

### Task 7: Add DOM structure tests for the refactored templates

**Files:**
- Create: `test/web/live/family_live/tree_connector_dom_test.exs`

- [ ] **Step 1: Write tests verifying the new DOM structure**

```elixir
defmodule Web.FamilyLive.TreeConnectorDomTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, family} = Families.create_family(%{name: "Connector Test Family"})

    {:ok, parent_a} =
      People.create_person(family, %{given_name: "Parent", surname: "A", gender: "male"})

    {:ok, parent_b} =
      People.create_person(family, %{given_name: "Parent", surname: "B", gender: "female"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Child", surname: "A", gender: "male"})

    {:ok, _} = Relationships.create_relationship(parent_a, parent_b, "married", %{})
    {:ok, _} = Relationships.create_relationship(parent_a, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent_b, child, "parent", %{role: "mother"})

    %{family: family, parent_a: parent_a, parent_b: parent_b, child: child}
  end

  describe "tree canvas hook" do
    test "tree canvas has TreeConnector hook", %{conn: conn, family: family, parent_a: parent_a} do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      assert has_element?(view, "#tree-canvas[phx-hook='TreeConnector']")
    end

    test "tree canvas has relative positioning class", %{
      conn: conn,
      family: family,
      parent_a: parent_a
    } do
      {:ok, _view, html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      assert html =~ ~s(id="tree-canvas")
      assert html =~ "relative"
    end
  end

  describe "couple card data attributes" do
    test "couple card retains data attributes", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      parent_b: parent_b
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      assert has_element?(view, "[data-couple-card][data-person-a-id='#{parent_a.id}']")
      assert has_element?(view, "[data-couple-card][data-person-b-id='#{parent_b.id}']")
    end
  end

  describe "children row data attributes" do
    test "child columns retain line origin and person id", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      child: child
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      assert has_element?(view, "[data-child-column][data-child-person-id='#{child.id}']")
      assert has_element?(view, "[data-line-origin='partner']")
    end
  end

  describe "no old hook references" do
    test "no BranchConnector, AncestorConnector, or ScrollToFocus in rendered HTML", %{
      conn: conn,
      family: family,
      parent_a: parent_a
    } do
      {:ok, _view, html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      refute html =~ "BranchConnector"
      refute html =~ "AncestorConnector"
      refute html =~ "ScrollToFocus"
    end
  end

  describe "no inline SVGs in couple cards" do
    test "couple card has no inline SVG elements", %{
      conn: conn,
      family: family,
      parent_a: parent_a
    } do
      {:ok, _view, html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      # Parse couple card area — should have no <svg> tags inside [data-couple-card]
      # The only SVGs should be the small icon SVGs inside person cards, not separator SVGs
      document = LazyHTML.from_fragment(html)
      couple_cards = LazyHTML.filter(document, "[data-couple-card]")

      for card <- couple_cards do
        # No direct SVG children that are separators (viewBox="0 0 40 123")
        separator_svgs = LazyHTML.filter(card, "svg[viewBox='0 0 40 123']")
        assert separator_svgs == []
      end
    end
  end

  describe "ex-partner separator spacers" do
    setup %{family: family, parent_a: parent_a} do
      {:ok, ex} =
        People.create_person(family, %{given_name: "Ex", surname: "Partner", gender: "female"})

      {:ok, _} = Relationships.create_relationship(parent_a, ex, "divorced", %{})

      %{ex: ex}
    end

    test "ex-partner separator is a div, not an svg", %{
      conn: conn,
      family: family,
      parent_a: parent_a,
      ex: ex
    } do
      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}?person=#{parent_a.id}")

      assert has_element?(view, "div[data-ex-separator='#{ex.id}']")
      refute has_element?(view, "svg[data-ex-separator='#{ex.id}']")
    end
  end
end
```

- [ ] **Step 2: Run the new tests**

Run: `cd /Users/babbage/Work/family && mix test test/web/live/family_live/tree_connector_dom_test.exs --trace`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/web/live/family_live/tree_connector_dom_test.exs
git commit -m "Add DOM structure tests for TreeConnector refactor"
```

---

### Task 8: Run full test suite and precommit

**Files:** (none — validation only)

- [ ] **Step 1: Run `mix precommit`**

Run: `cd /Users/babbage/Work/family && mix precommit`

Expected: Compilation (warnings-as-errors), formatting, and all tests pass.

- [ ] **Step 2: Fix any issues found by precommit**

Common issues:
- Unused variables from removed `connector_id` assigns — should already be cleaned up in Task 5
- Formatting issues — fix with `mix format`

- [ ] **Step 3: Manual verification**

Start the dev server and visually verify connectors:

Run: `cd /Users/babbage/Work/family && iex -S mix phx.server`

Open `http://localhost:4000` and navigate to a family with:
1. A couple with shared children → solid T/comb connector
2. A person with ex-partners and children → dashed connectors with Y-offset stacking
3. A person with parents (ancestors above) → ancestor connectors
4. Change focus person → connectors redraw, scroll-to-focus works
5. Resize browser window → connectors redraw correctly

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "Fix precommit issues for SVG path connectors refactor"
```
