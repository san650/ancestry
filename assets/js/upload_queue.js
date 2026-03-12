const UploadQueue = {
  mounted() {
    this.queue = []
    this.currentBatch = []
    this.awaitingBatchComplete = false
    this.feedingBatch = false
    this.dragCounter = 0

    this.fileInput = document.querySelector('#upload-form [type=file]')

    // File input change: user selected files via OS picker.
    // LiveView's live_file_input handler already registered and started
    // uploading these files — we must NOT call feedNextBatch here, because
    // that would set fileInput.files again and dispatch a second change
    // event, making LiveView create duplicate entries and breaking the
    // entries.length === currentBatch.length check in updated().
    this.fileInput.addEventListener("change", (e) => {
      if (this.feedingBatch) return
      const files = Array.from(e.target.files)
      if (files.length === 0) return

      this.queue = [...files]
      this.currentBatch = this.queue.splice(0, 10)
      this.awaitingBatchComplete = false

      this.pushEvent("queue_files", {
        files: files.map((f) => ({ name: f.name, size: f.size })),
      })
    })

    // Drag events on document so the overlay covers the entire page,
    // including the toolbar and any other area outside #gallery-show-root.
    // Store bound references so we can remove them in destroyed().
    this._onDragEnter = (e) => {
      e.preventDefault()
      this.dragCounter++
      if (this.dragCounter === 1) this.showDragOverlay(e)
    }

    this._onDragLeave = (e) => {
      e.preventDefault()
      this.dragCounter--
      if (this.dragCounter === 0) this.hideDragOverlay()
    }

    this._onDragOver = (e) => {
      e.preventDefault()
    }

    this._onDrop = (e) => {
      e.preventDefault()
      this.dragCounter = 0
      this.hideDragOverlay()

      const files = Array.from(e.dataTransfer.files).filter(
        (f) => f.type.startsWith("image/") || f.name.match(/\.(dng|nef|tiff?|raw)$/i)
      )
      if (files.length > 0) this.queueFiles(files)
    }

    document.addEventListener("dragenter", this._onDragEnter)
    document.addEventListener("dragleave", this._onDragLeave)
    document.addEventListener("dragover", this._onDragOver)
    document.addEventListener("drop", this._onDrop)

    // Server signals current batch is fully consumed — feed next.
    // Use requestAnimationFrame to let LiveView finish clearing consumed
    // entries from the DOM before we set new files on the input.
    this.handleEvent("batch_complete", () => {
      this.awaitingBatchComplete = false
      requestAnimationFrame(() => this.feedNextBatch())
    })

    // Server signals upload was cancelled — reset all hook state
    this.handleEvent("reset_queue", () => {
      this.queue = []
      this.currentBatch = []
      this.awaitingBatchComplete = false
    })
  },

  destroyed() {
    document.removeEventListener("dragenter", this._onDragEnter)
    document.removeEventListener("dragleave", this._onDragLeave)
    document.removeEventListener("dragover", this._onDragOver)
    document.removeEventListener("drop", this._onDrop)
  },

  // Upload completion is now detected server-side via handle_progress.
  updated() {},

  // Called only for drag-and-drop uploads (not upload button).
  // Sends queue_files metadata, then feeds files to the file input via
  // feedNextBatch so LiveView's auto-upload picks them up.
  queueFiles(files) {
    this.queue = [...files]

    this.pushEvent("queue_files", {
      files: files.map((f) => ({ name: f.name, size: f.size })),
    })

    this.feedNextBatch()
  },

  feedNextBatch() {
    if (this.queue.length === 0) {
      this.currentBatch = []
      return
    }

    const batch = this.queue.splice(0, 10)
    this.currentBatch = batch

    const dt = new DataTransfer()
    batch.forEach((f) => dt.items.add(f))

    this.feedingBatch = true
    this.fileInput.files = dt.files
    this.fileInput.dispatchEvent(new Event("change", { bubbles: true }))
    this.feedingBatch = false
  },

  showDragOverlay(e) {
    const count = e.dataTransfer?.items?.length || 0
    const overlay = document.getElementById("drag-overlay")
    if (!overlay) return
    const label = overlay.querySelector("[data-drag-count]")
    if (label) {
      label.textContent = `Drop to upload ${count} photo${count !== 1 ? "s" : ""}`
    }
    overlay.classList.remove("hidden")
  },

  hideDragOverlay() {
    const overlay = document.getElementById("drag-overlay")
    if (overlay) overlay.classList.add("hidden")
  },
}

export default UploadQueue
