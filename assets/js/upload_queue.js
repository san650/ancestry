const UploadQueue = {
  mounted() {
    this.queue = []
    this.currentBatch = []
    this.awaitingBatchComplete = false
    this.feedingBatch = false
    this.dragCounter = 0

    this.fileInput = document.querySelector('#upload-form [type=file]')

    // File input change: user selected files via OS picker
    this.fileInput.addEventListener("change", (e) => {
      if (this.feedingBatch) return
      const files = Array.from(e.target.files)
      if (files.length > 0) this.queueFiles(files)
    })

    // Drag events on the gallery wrapper
    this.el.addEventListener("dragenter", (e) => {
      e.preventDefault()
      this.dragCounter++
      if (this.dragCounter === 1) this.showDragOverlay(e)
    })

    this.el.addEventListener("dragleave", (e) => {
      e.preventDefault()
      this.dragCounter--
      if (this.dragCounter === 0) this.hideDragOverlay()
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.dragCounter = 0
      this.hideDragOverlay()

      const files = Array.from(e.dataTransfer.files).filter(
        (f) => f.type.startsWith("image/") || f.name.match(/\.(dng|nef|tiff?|raw)$/i)
      )
      if (files.length > 0) this.queueFiles(files)
    })

    // Server signals current batch is fully consumed — feed next
    this.handleEvent("batch_complete", () => {
      this.awaitingBatchComplete = false
      this.feedNextBatch()
    })

    // Server signals upload was cancelled — reset all hook state
    this.handleEvent("reset_queue", () => {
      this.queue = []
      this.currentBatch = []
      this.awaitingBatchComplete = false
    })
  },

  updated() {
    if (this.awaitingBatchComplete || this.currentBatch.length === 0) return

    const entries = this.el.querySelectorAll("[data-upload-entry]")
    if (entries.length !== this.currentBatch.length) return

    const allSettled = Array.from(entries).every(
      (e) => parseInt(e.dataset.progress || "0") === 100 || e.dataset.error === "true"
    )

    if (allSettled) {
      this.awaitingBatchComplete = true
      this.pushEvent("upload_photos", {})
    }
  },

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
