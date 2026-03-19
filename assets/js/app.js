// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/ancestry"
import topbar from "../vendor/topbar"
import { PhotoTagger, PersonHighlight } from "./photo_tagger"

function stripDiacritics(str) {
  return str.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
}

const FuzzyFilter = {
  mounted() {
    const targetId = this.el.dataset.target
    this.el.addEventListener("input", (e) => {
      const query = stripDiacritics(e.target.value.trim())
      const container = document.getElementById(targetId)
      if (!container) return
      const items = container.querySelectorAll("[data-filter-name]")
      items.forEach((item) => {
        if (!query || item.dataset.filterName.includes(query)) {
          item.style.display = ""
        } else {
          item.style.display = "none"
        }
      })
    })
  }
}

function makeSvgLine(svg, x1, y1, x2, y2, stroke, dashArray) {
  const l = document.createElementNS("http://www.w3.org/2000/svg", "line")
  l.setAttribute("x1", x1); l.setAttribute("y1", y1)
  l.setAttribute("x2", x2); l.setAttribute("y2", y2)
  l.setAttribute("stroke", stroke); l.setAttribute("stroke-width", "3")
  if (dashArray) l.setAttribute("stroke-dasharray", dashArray)
  svg.appendChild(l)
}

const CONNECTOR_STROKE = "rgba(128,128,128,0.2)"

const BranchConnector = {
  mounted() { this.draw() },
  updated() { this.draw() },
  draw() {
    requestAnimationFrame(() => {
      const svg = this.el.querySelector("svg")
      if (!svg) return
      const containerRect = this.el.getBoundingClientRect()
      const childrenRow = this.el.nextElementSibling
      if (!childrenRow) return
      const columns = childrenRow.querySelectorAll(":scope > [data-child-column]")
      if (columns.length === 0) return

      // Find the couple card above (sibling of the subtree_children wrapper)
      const coupleCard = this.el.parentElement.previousElementSibling

      const h = 20
      const barY = h / 2
      const exDelta = 5

      // Group children by line origin
      const groups = {}
      Array.from(columns).forEach(col => {
        const origin = col.dataset.lineOrigin || "partner"
        if (!groups[origin]) groups[origin] = []
        const childId = col.dataset.childPersonId
        let cx
        if (childId) {
          const personEl = col.querySelector(`[data-person-id="${childId}"]`)
          if (personEl) {
            const r = personEl.getBoundingClientRect()
            cx = r.left + r.width / 2 - containerRect.left
          }
        }
        if (cx === undefined) {
          const r = col.getBoundingClientRect()
          cx = r.left + r.width / 2 - containerRect.left
        }
        groups[origin].push(cx)
      })

      // Compute origin X for each group type
      function getOriginX(origin) {
        if (coupleCard) {
          if (origin === "partner") {
            const aId = coupleCard.dataset.personAId
            const bId = coupleCard.dataset.personBId
            if (aId && bId) {
              const a = coupleCard.querySelector(`[data-person-id="${aId}"]`)
              const b = coupleCard.querySelector(`[data-person-id="${bId}"]`)
              if (a && b) {
                const aR = a.getBoundingClientRect()
                const bR = b.getBoundingClientRect()
                return (aR.left + aR.width / 2 + bR.left + bR.width / 2) / 2 - containerRect.left
              }
            }
          } else if (origin === "solo") {
            const aId = coupleCard.dataset.personAId
            if (aId) {
              const a = coupleCard.querySelector(`[data-person-id="${aId}"]`)
              if (a) {
                const r = a.getBoundingClientRect()
                return r.left + r.width / 2 - containerRect.left
              }
            }
          } else if (origin.startsWith("ex-")) {
            const exId = origin.replace("ex-", "")
            const sep = coupleCard.querySelector(`[data-ex-separator="${exId}"]`)
            if (sep) {
              const r = sep.getBoundingClientRect()
              return r.left + r.width / 2 - containerRect.left
            }
          }
        }
        return containerRect.width / 2
      }

      while (svg.firstChild) svg.removeChild(svg.firstChild)

      // Draw connectors for each group
      for (const [origin, centers] of Object.entries(groups)) {
        const originX = getOriginX(origin)
        const isDashed = origin.startsWith("ex-")
        const dash = isDashed ? "6,4" : null
        const exDelta = 8

        // All X positions for this group (origin + children)
        const allX = [originX, ...centers]
        const left = Math.min(...allX)
        const right = Math.max(...allX)

        // Vertical from origin down to bar
        makeSvgLine(svg, originX, 0, originX, dash ? barY - exDelta : barY, CONNECTOR_STROKE, dash)
        // Horizontal bar (skip if all points align)
        if (left !== right) {
          makeSvgLine(svg, left, dash ? barY - exDelta : barY, right, dash ? barY - exDelta : barY, CONNECTOR_STROKE, dash)
        }
        // Vertical from bar down to each child
        centers.forEach(cx => makeSvgLine(svg, cx, barY, cx, h, CONNECTOR_STROKE, dash))
      }

      svg.setAttribute("viewBox", `0 0 ${containerRect.width} ${h}`)
      svg.style.width = containerRect.width + "px"
      svg.style.height = h + "px"
    })
  }
}

// AncestorConnector uses the exact same drawing logic as BranchConnector
// but mirrors the direction: N parent couples above → bar → N child persons below.
const AncestorConnector = {
  mounted() { this.draw() },
  updated() { this.draw() },
  draw() {
    requestAnimationFrame(() => {
      const svg = this.el.querySelector("svg")
      if (!svg) return
      const containerRect = this.el.getBoundingClientRect()
      const parentsRow = this.el.previousElementSibling
      if (!parentsRow) return
      const parentColumns = parentsRow.querySelectorAll(":scope > [data-ancestor-parent-column]")
      if (parentColumns.length === 0) return

      const h = 20

      // Source: bottom couple card in each parent column (direct child only, not nested)
      const parentCenters = Array.from(parentColumns).map(col => {
        const subtreeRoot = col.children[0]
        const bottomCouple = subtreeRoot?.querySelector(":scope > [data-couple-card]")
        const target = bottomCouple || col
        const r = target.getBoundingClientRect()
        return r.left + r.width / 2 - containerRect.left
      })

      // Target: specific person by ID within the couple card below
      const coupleCardBelow = this.el.nextElementSibling
      const childTargets = Array.from(parentColumns).map(col => {
        const targetId = col.dataset.targetPersonId
        if (targetId && coupleCardBelow) {
          const personEl = coupleCardBelow.querySelector(`[data-person-id="${targetId}"]`)
          if (personEl) {
            const r = personEl.getBoundingClientRect()
            return r.left + r.width / 2 - containerRect.left
          }
        }
        return containerRect.width / 2
      })

      while (svg.firstChild) svg.removeChild(svg.firstChild)

      // Same pattern as BranchConnector: verticals → bar → verticals
      const barY = h / 2

      parentCenters.map((p, i) => {
        makeSvgLine(svg, p, barY, childTargets[i], barY, CONNECTOR_STROKE)
      })

      parentCenters.forEach(cx => makeSvgLine(svg, cx, 0, cx, barY, CONNECTOR_STROKE))
      childTargets.forEach(cx => makeSvgLine(svg, cx, barY, cx, h, CONNECTOR_STROKE))

      svg.setAttribute("viewBox", `0 0 ${containerRect.width} ${h}`)
      svg.style.width = containerRect.width + "px"
      svg.style.height = h + "px"
    })
  }
}

// In the TreeView when chaning the focus person, scroll the page so the focus person is visible.
const ScrollToFocus = {
  mounted() {
    this.handleEvent("scroll_to_focus", () => this.scrollToFocus())
    this.scrollToFocus()
  },
  scrollToFocus() {
    setTimeout(() => {
      const target = this.el.querySelector("#focus-person-card")
      if (!target) return

      target.scrollIntoView({
        behavior: "smooth",
        block: "center",
        inline: "center"
      })
    }, 50)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, FuzzyFilter, BranchConnector, AncestorConnector, ScrollToFocus, PhotoTagger, PersonHighlight },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

