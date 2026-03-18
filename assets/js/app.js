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
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/family"
import topbar from "../vendor/topbar"

const FuzzyFilter = {
  mounted() {
    const targetId = this.el.dataset.target
    this.el.addEventListener("input", (e) => {
      const query = e.target.value.toLowerCase().trim()
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

      const h = 20
      const centers = Array.from(columns).map(col => {
        const r = col.getBoundingClientRect()
        return r.left + r.width / 2 - containerRect.left
      })
      const parentCx = containerRect.width / 2
      const stroke = "rgba(128,128,128,0.2)"

      while (svg.firstChild) svg.removeChild(svg.firstChild)

      const makeLine = (x1, y1, x2, y2) => {
        const l = document.createElementNS("http://www.w3.org/2000/svg", "line")
        l.setAttribute("x1", x1); l.setAttribute("y1", y1)
        l.setAttribute("x2", x2); l.setAttribute("y2", y2)
        l.setAttribute("stroke", stroke); l.setAttribute("stroke-width", "1")
        svg.appendChild(l)
      }

      if (centers.length === 1) {
        makeLine(centers[0], 0, centers[0], h)
      } else {
        const left = Math.min(...centers)
        const right = Math.max(...centers)
        const barY = h / 2
        makeLine(parentCx, 0, parentCx, barY)
        makeLine(left, barY, right, barY)
        centers.forEach(cx => makeLine(cx, barY, cx, h))
      }

      svg.setAttribute("viewBox", `0 0 ${containerRect.width} ${h}`)
      svg.style.width = containerRect.width + "px"
      svg.style.height = h + "px"
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, FuzzyFilter, BranchConnector},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
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
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
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
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

