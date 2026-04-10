// Import the vendored Trix UMD bundle — registers <trix-editor> custom element
import "../vendor/trix.js"

const TrixEditor = {
  mounted() {
    const editorEl = this.el.querySelector("trix-editor")
    if (!editorEl) return

    this.editorEl = editorEl
    this.mentionDropdown = null
    this.mentionQuery = null
    this.selectedIndex = 0

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
      this._checkForMention()
    })

    // Handle Insert Photo button
    const insertBtn = this.el.querySelector("[data-action='insert-photo']")
    if (insertBtn) {
      insertBtn.addEventListener("click", (e) => {
        e.preventDefault()
        this.pushEvent("open_content_picker", {})
      })
    }

    // Keyboard handling for mention dropdown
    this.el.addEventListener("keydown", (e) => {
      if (this.mentionDropdown) {
        if (e.key === "ArrowDown" || e.key === "ArrowUp") {
          e.preventDefault()
          this._navigateDropdown(e.key === "ArrowDown" ? 1 : -1)
        } else if (e.key === "Enter" && this._getSelectedItem()) {
          e.preventDefault()
          this._selectMention(this._getSelectedItem())
        } else if (e.key === "Escape") {
          e.preventDefault()
          this._closeMentionDropdown()
        }
      }
    })

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

  _checkForMention() {
    const editor = this.editorEl.editor
    const position = editor.getPosition()
    const text = editor.getDocument().toString().slice(0, position)
    const match = text.match(/(?:^|[^a-zA-Z0-9])@([a-zA-Z0-9 ]{0,30})$/)

    if (match) {
      const query = match[1]
      if (query.length >= 1) {
        this.mentionQuery = query
        this.mentionStart = position - query.length - 1
        this.pushEvent("search_mentions", { query })
      }
    } else {
      this._closeMentionDropdown()
    }
  },

  _showMentionDropdown(results) {
    this._closeMentionDropdown()
    if (results.length === 0) return

    const dropdown = document.createElement("div")
    dropdown.className = "absolute z-50 bg-white shadow-lg rounded border border-gray-200 py-1 max-h-48 overflow-y-auto"
    dropdown.style.minWidth = "200px"

    results.forEach((person, index) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = `w-full text-left px-3 py-2 text-sm hover:bg-gray-100 ${index === 0 ? "bg-gray-50" : ""}`
      item.dataset.personId = person.id
      item.dataset.personName = person.name
      item.dataset.index = index
      item.textContent = person.name
      item.addEventListener("click", () => this._selectMention(item))
      dropdown.appendChild(item)
    })

    // Position near the editor
    const editorRect = this.editorEl.getBoundingClientRect()
    const wrapperRect = this.el.getBoundingClientRect()
    dropdown.style.position = "absolute"
    dropdown.style.bottom = "auto"
    dropdown.style.top = `${editorRect.bottom - wrapperRect.top + 4}px`
    dropdown.style.left = "0px"

    this.el.style.position = "relative"
    this.el.appendChild(dropdown)
    this.mentionDropdown = dropdown
    this.selectedIndex = 0
  },

  _closeMentionDropdown() {
    if (this.mentionDropdown) {
      this.mentionDropdown.remove()
      this.mentionDropdown = null
      this.mentionQuery = null
      this.selectedIndex = 0
    }
  },

  _navigateDropdown(direction) {
    if (!this.mentionDropdown) return
    const items = this.mentionDropdown.querySelectorAll("button")
    if (items[this.selectedIndex]) items[this.selectedIndex].classList.remove("bg-gray-50")
    this.selectedIndex = Math.max(0, Math.min(items.length - 1, this.selectedIndex + direction))
    if (items[this.selectedIndex]) items[this.selectedIndex].classList.add("bg-gray-50")
  },

  _getSelectedItem() {
    if (!this.mentionDropdown) return null
    return this.mentionDropdown.querySelectorAll("button")[this.selectedIndex]
  },

  _selectMention(item) {
    const personId = item.dataset.personId
    const personName = item.dataset.personName
    const editor = this.editorEl.editor

    // Delete the @query text
    const position = editor.getPosition()
    const deleteCount = (this.mentionQuery?.length || 0) + 1 // +1 for @
    editor.setSelectedRange([position - deleteCount, position])
    editor.deleteInDirection("forward")

    // Insert mention as attachment
    const attachment = new Trix.Attachment({
      contentType: "application/vnd.memory-mention",
      content: `<span data-person-id="${personId}">@${personName}</span>`,
    })
    editor.insertAttachment(attachment)

    this._closeMentionDropdown()
  },
}

export { TrixEditor }
