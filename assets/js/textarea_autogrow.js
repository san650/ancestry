// TextareaAutogrow — resizes a textarea to fit its content, up to its CSS max-height.
// Attach via `phx-hook="TextareaAutogrow"`. Set `max-h-*` on the textarea to cap
// the maximum height. Above the cap, the textarea scrolls internally.
//
// As the textarea grows it may push below the visible viewport (when it lives
// inside a scrollable panel). On input, we scroll the nearest scrollable
// ancestor so the textarea's bottom edge stays in view.
const TextareaAutogrow = {
  mounted() {
    this.resize()
    this.el.addEventListener("input", () => {
      this.resize()
      this.scrollIntoView()
    })
    this.el.addEventListener("focus", () => this.scrollIntoView())
  },

  // Re-run after LiveView updates (e.g. the textarea value was reset after form submit).
  updated() {
    this.resize()
  },

  resize() {
    // Reset to auto so scrollHeight reflects the content size, not the current size.
    this.el.style.height = "auto"
    this.el.style.height = this.el.scrollHeight + "px"
  },

  scrollIntoView() {
    // Keep the bottom of the textarea visible inside whichever ancestor scrolls.
    // `block: "nearest"` scrolls the minimum amount needed — no-op if already visible.
    this.el.scrollIntoView({ block: "nearest", behavior: "instant" })
  },
}

export default TextareaAutogrow
