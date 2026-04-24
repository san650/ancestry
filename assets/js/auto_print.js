// assets/js/auto_print.js
//
// AutoPrint — triggers window.print() after the page has rendered.
// Waits for the GraphConnector hook to finish drawing SVG connectors,
// then zooms the page to fit the tree within the printable width.

const AutoPrint = {
  mounted() {
    // Give the GraphConnector hook time to draw SVG connectors,
    // then scale to fit and trigger the print dialog.
    setTimeout(() => {
      this._scaleToFit()
      window.print()
    }, 500)

    window.addEventListener("afterprint", this._onAfterPrint = () => {
      document.body.style.zoom = ""
    })
  },

  destroyed() {
    if (this._onAfterPrint) {
      window.removeEventListener("afterprint", this._onAfterPrint)
    }
    document.body.style.zoom = ""
  },

  _scaleToFit() {
    const grid = document.querySelector("[data-graph-grid]")
    if (!grid) return

    const gridWidth = grid.scrollWidth
    const availableWidth = window.innerWidth
    if (gridWidth > availableWidth && availableWidth > 0) {
      const zoom = availableWidth / gridWidth
      document.body.style.zoom = zoom
    }
  },
}

export { AutoPrint }
