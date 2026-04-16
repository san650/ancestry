// TextareaAutogrow — resizes a textarea to fit its content, up to its CSS max-height.
// Attach via `phx-hook="TextareaAutogrow"`. Set `max-h-*` on the textarea to cap
// the maximum height. Above the cap, the textarea scrolls internally.
const TextareaAutogrow = {
  mounted() {
    this.resize()
    this.el.addEventListener("input", () => this.resize())
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
}

export default TextareaAutogrow
