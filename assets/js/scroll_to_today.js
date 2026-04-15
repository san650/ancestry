export const ScrollToToday = {
  mounted() {
    this.el.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
