export const TreeDrawer = {
  mounted() {
    this.expanded = false
    this.panel = this.el.querySelector("[data-drawer-panel]")

    this.el.querySelector("[data-drawer-toggle]")?.addEventListener("click", () => {
      this.expanded = !this.expanded
      this.updateState()
    })
  },

  updateState() {
    if (!this.panel) return
    if (this.expanded) {
      this.panel.classList.remove("max-h-0", "opacity-0")
      this.panel.classList.add("max-h-[200px]", "opacity-100")
    } else {
      this.panel.classList.remove("max-h-[200px]", "opacity-100")
      this.panel.classList.add("max-h-0", "opacity-0")
    }
  },

  destroyed() {
    if (!this.panel) return
  }
}
