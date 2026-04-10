// Import the vendored Trix UMD bundle — registers <trix-editor> custom element
import "../vendor/trix.js"

const TrixEditor = {
  mounted() {
    const editorEl = this.el.querySelector("trix-editor")
    if (!editorEl) return

    this.editorEl = editorEl

    // Block file uploads (drag/drop/paste)
    this.el.addEventListener("trix-file-accept", (e) => {
      e.preventDefault()
    })

    // Sync content to hidden input on change
    this.el.addEventListener("trix-change", () => {
      const input = this.el.querySelector("input[type=hidden]")
      if (input) {
        const doc = editorEl.editor.getDocument().toString()
        input.value = doc !== "\n" ? editorEl.innerHTML : ""
        input.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })

    // Handle Insert Photo button
    const insertBtn = this.el.querySelector("[data-action='insert-photo']")
    if (insertBtn) {
      insertBtn.addEventListener("click", (e) => {
        e.preventDefault()
        this.pushEvent("open_content_picker", {})
      })
    }

    // Receive photo insertion from LiveView
    this.handleEvent("insert_photo", ({ url, photo_id }) => {
      const attachment = new Trix.Attachment({
        contentType: "application/vnd.memory-photo",
        content: `<img data-photo-id="${photo_id}" src="${url}" class="max-w-full rounded" />`,
      })
      editorEl.editor.insertAttachment(attachment)
    })

    // Receive mention search results from LiveView
    this.handleEvent("mention_results", ({ results }) => {
      this._showMentionDropdown(results)
    })
  },

  destroyed() {
    this._closeMentionDropdown()
  },

  // Mention dropdown methods will be added in Task 14
  _showMentionDropdown(results) {},
  _closeMentionDropdown() {}
}

export { TrixEditor }
