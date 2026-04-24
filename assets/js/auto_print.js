// assets/js/auto_print.js
//
// AutoPrint — triggers window.print() after the page has rendered.
// Waits for the GraphConnector hook to finish drawing SVG connectors.

const AutoPrint = {
  mounted() {
    // Give the GraphConnector hook time to draw SVG connectors,
    // then trigger the print dialog.
    setTimeout(() => window.print(), 500)
  },
}

export { AutoPrint }
