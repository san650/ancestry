export const ScrollToToday = {
  mounted() {
    // Defer scroll to after the browser has painted the new DOM.
    // On live navigation, mounted() fires before layout is complete,
    // so scrollIntoView would target an un-positioned element.
    requestAnimationFrame(() => {
      this.el.scrollIntoView({ behavior: "smooth", block: "center" })
    })
  }
}
