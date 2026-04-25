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

    // Wait for Trix to initialize before customizing toolbar
    if (editorEl.editor) {
      this._setupEditor()
    } else {
      editorEl.addEventListener("trix-initialize", () => this._setupEditor(), { once: true })
    }
  },

  _setupEditor() {
    const editorEl = this.editorEl

    // Remove the attach files button from the toolbar
    const toolbar = editorEl.toolbarElement
    if (toolbar) {
      const fileTools = toolbar.querySelector("[data-trix-button-group='file-tools']")
      if (fileTools) fileTools.remove()

      // Add "Insert Photo" button to the toolbar
      const blockTools = toolbar.querySelector("[data-trix-button-group='block-tools']")
      if (blockTools) {
        const photoBtn = document.createElement("button")
        photoBtn.type = "button"
        photoBtn.className = "trix-button"
        photoBtn.dataset.action = "insert-photo"
        photoBtn.title = "Insert Photo"
        photoBtn.tabIndex = -1
        photoBtn.textContent = "📷 Photo"
        photoBtn.addEventListener("click", (e) => {
          e.preventDefault()
          this.pushEvent("open_content_picker", {})
        })

        // Create a new button group for custom tools
        const customGroup = document.createElement("span")
        customGroup.className = "trix-button-group"
        customGroup.appendChild(photoBtn)
        blockTools.parentNode.insertBefore(customGroup, blockTools.nextSibling)
      }
    }

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

    // Receive newly created person from QuickPersonModal — insert as mention
    this.handleEvent("mention_created", ({ id, name }) => {
      const editor = this.editorEl.editor
      const start = this._savedMentionStart
      const query = this._savedMentionQuery

      if (start != null && query != null) {
        // Delete the @query text (start already points at the @ character)
        const deleteEnd = start + query.length + 1 // +1 for the @ symbol
        editor.setSelectedRange([start, deleteEnd])
        editor.deleteInDirection("backward")
      }

      // Insert mention attachment using the same pattern as _selectMention
      const attachment = new Trix.Attachment({
        contentType: "application/vnd.memory-mention",
        content: `<span data-person-id="${id}">@${name}</span>`,
      })
      editor.insertAttachment(attachment)

      // Cleanup saved state
      this._savedMentionStart = null
      this._savedMentionQuery = null
    })

    // QuickPersonModal was cancelled — just clean up saved state
    this.handleEvent("mention_cancelled", () => {
      this._savedMentionStart = null
      this._savedMentionQuery = null
    })
  },

  destroyed() {
    this._closeMentionDropdown()
  },

  _checkForMention() {
    try {
      const editor = this.editorEl.editor
      if (!editor) return

      // Use getSelectedRange which is the stable Trix v2 API
      const range = editor.getSelectedRange()
      const position = range[0]
      const text = editor.getDocument().toString().slice(0, position)
      const match = text.match(/(?:^|[^\p{L}\p{N}])@([\p{L}\p{N} ]{0,30})$/u)

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
    } catch (e) {
      console.error("TrixEditor: _checkForMention error:", e)
    }
  },

  _showMentionDropdown(results) {
    // Remove old dropdown DOM but preserve mentionQuery/mentionStart state —
    // _closeMentionDropdown resets them, which breaks _selectMention later.
    if (this.mentionDropdown) {
      this.mentionDropdown.remove()
      this.mentionDropdown = null
    }
    this.selectedIndex = 0
    if ((!results || results.length === 0) && (!this.mentionQuery || this.mentionQuery.length < 1)) return

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
      item.addEventListener("mousedown", (e) => {
        e.preventDefault() // keep focus in Trix editor
        this._selectMention(item)
      })
      dropdown.appendChild(item)
    })

    // "Create person" button at the bottom of the dropdown
    if (this.mentionQuery && this.mentionQuery.length >= 1) {
      const divider = document.createElement("div")
      divider.className = "border-t border-gray-200 mt-1 pt-1"

      const createBtn = document.createElement("button")
      createBtn.type = "button"
      createBtn.className = "w-full text-left px-3 py-2 text-sm hover:bg-emerald-50 text-emerald-600 flex items-center gap-2"

      const plusSpan = document.createElement("span")
      plusSpan.className = "w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center shrink-0 text-emerald-600 text-xs font-bold"
      plusSpan.textContent = "+"
      createBtn.appendChild(plusSpan)

      const label = document.createElement("span")
      const truncated = this.mentionQuery.length > 20 ? this.mentionQuery.substring(0, 20) + "..." : this.mentionQuery
      label.textContent = `Create "${truncated}"`
      createBtn.appendChild(label)

      createBtn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        // Save cursor position for later insertion — _closeMentionDropdown
        // resets mentionQuery to null, so we must capture these first.
        this._savedMentionStart = this.mentionStart
        this._savedMentionQuery = this.mentionQuery

        this.pushEvent("create_person_from_mention", { query: this.mentionQuery })
        this._closeMentionDropdown()
      })

      divider.appendChild(createBtn)
      dropdown.appendChild(divider)
    }

    // Position near the text cursor using browser selection API
    const sel = window.getSelection()
    const wrapperRect = this.el.getBoundingClientRect()
    let top = 0
    let left = 0

    if (sel && sel.rangeCount > 0) {
      const range = sel.getRangeAt(0)
      const caretRect = range.getBoundingClientRect()
      top = caretRect.bottom - wrapperRect.top + 4
      left = caretRect.left - wrapperRect.left
    } else {
      // Fallback: bottom of editor
      const editorRect = this.editorEl.getBoundingClientRect()
      top = editorRect.bottom - wrapperRect.top + 4
      left = 0
    }

    dropdown.style.position = "absolute"
    dropdown.style.top = `${top}px`
    dropdown.style.left = `${left}px`

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

    // Three-step replacement pattern (from trix-mentions-element):
    // 1. Select the @query range using saved positions
    // 2. Delete the selected text
    // 3. Insert the attachment at the now-empty cursor
    const start = this.mentionStart
    const end = start + (this.mentionQuery?.length || 0) + 1 // +1 for @
    editor.setSelectedRange([start, end])
    editor.deleteInDirection("backward")

    const attachment = new Trix.Attachment({
      contentType: "application/vnd.memory-mention",
      content: `<span data-person-id="${personId}">@${personName}</span>`,
    })
    editor.insertAttachment(attachment)

    this._closeMentionDropdown()
    this.editorEl.focus({ preventScroll: true })
  },
}

export { TrixEditor }
