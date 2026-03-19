const PhotoTagger = {
  mounted() {
    const inner = this.el.querySelector("#photo-tagger-inner")
    this.image = inner.querySelector("#lightbox-image")
    this.circlesContainer = inner.querySelector("#tag-circles")
    this.popover = inner.querySelector("#tag-popover")
    this.pendingClick = null

    this.image.addEventListener("click", (e) => {
      const rect = this.image.getBoundingClientRect()
      const x = (e.clientX - rect.left) / rect.width
      const y = (e.clientY - rect.top) / rect.height

      this.pendingClick = { x, y }
      this.showPopover(e.clientX - rect.left, e.clientY - rect.top, rect)
    })

    this.handleEvent("photo_people_updated", ({ people }) => {
      this.renderCircles(people)
      this.hidePopover()
    })

    this.handleEvent("highlight_person", ({ person_id }) => {
      this.highlightCircle(person_id)
    })

    this.handleEvent("unhighlight_person", ({ person_id }) => {
      this.unhighlightCircle(person_id)
    })
  },

  showPopover(left, top, imageRect) {
    const popoverWidth = 256
    const popoverLeft = Math.min(left, imageRect.width - popoverWidth - 8)

    this.popover.replaceChildren()
    const wrapper = document.createElement("div")
    wrapper.className = "bg-neutral-900 border border-white/20 rounded-xl shadow-2xl w-64 overflow-hidden"

    const inputWrap = document.createElement("div")
    inputWrap.className = "px-3 py-2 border-b border-white/10"
    const input = document.createElement("input")
    input.id = "tag-search-input"
    input.type = "text"
    input.placeholder = "Search people..."
    input.className = "w-full bg-transparent border-none text-sm text-white placeholder-white/40 focus:outline-none"
    inputWrap.appendChild(input)
    wrapper.appendChild(inputWrap)

    const resultsDiv = document.createElement("div")
    resultsDiv.id = "tag-search-results"
    resultsDiv.className = "max-h-48 overflow-y-auto p-1"
    const hint = document.createElement("p")
    hint.className = "text-xs text-white/30 px-2 py-3 text-center"
    hint.textContent = "Type to search"
    resultsDiv.appendChild(hint)
    wrapper.appendChild(resultsDiv)

    this.popover.appendChild(wrapper)
    this.popover.style.left = Math.max(0, popoverLeft) + "px"
    this.popover.style.top = Math.min(top + 24, imageRect.height - 200) + "px"
    this.popover.classList.remove("hidden")

    setTimeout(() => input.focus(), 50)

    let debounceTimer = null
    input.addEventListener("input", (e) => {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        this.pushEvent("search_people_for_tag", { query: e.target.value }, (reply) => {
          this.renderSearchResults(reply.results)
        })
      }, 300)
    })

    input.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.stopPropagation()
        this.hidePopover()
      }
    })

    setTimeout(() => {
      this._clickAway = (e) => {
        if (!this.popover.contains(e.target) && e.target !== this.image) {
          this.hidePopover()
        }
      }
      document.addEventListener("click", this._clickAway)
    }, 100)
  },

  hidePopover() {
    this.popover.classList.add("hidden")
    this.popover.replaceChildren()
    this.pendingClick = null
    if (this._clickAway) {
      document.removeEventListener("click", this._clickAway)
      this._clickAway = null
    }
  },

  renderSearchResults(results) {
    const container = this.popover.querySelector("#tag-search-results")
    if (!container) return
    container.replaceChildren()

    if (results.length === 0) {
      const p = document.createElement("p")
      p.className = "text-xs text-white/30 px-2 py-3 text-center"
      p.textContent = "No results"
      container.appendChild(p)
      return
    }

    results.forEach(person => {
      const btn = document.createElement("button")
      btn.dataset.personId = person.id
      btn.className = "flex items-center gap-2 w-full px-2 py-1.5 rounded-lg hover:bg-white/10 transition-colors text-left"

      if (person.has_photo) {
        const img = document.createElement("img")
        img.src = person.photo_url
        img.className = "w-6 h-6 rounded-full object-cover shrink-0"
        btn.appendChild(img)
      } else {
        const placeholder = document.createElement("div")
        placeholder.className = "w-6 h-6 rounded-full bg-white/10 flex items-center justify-center shrink-0"
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
        svg.setAttribute("class", "w-3.5 h-3.5 text-white/40")
        svg.setAttribute("fill", "none")
        svg.setAttribute("viewBox", "0 0 24 24")
        svg.setAttribute("stroke", "currentColor")
        const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
        path.setAttribute("stroke-linecap", "round")
        path.setAttribute("stroke-linejoin", "round")
        path.setAttribute("stroke-width", "2")
        path.setAttribute("d", "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z")
        svg.appendChild(path)
        placeholder.appendChild(svg)
        btn.appendChild(placeholder)
      }

      const nameSpan = document.createElement("span")
      nameSpan.className = "text-sm text-white/80 truncate"
      nameSpan.textContent = person.name
      btn.appendChild(nameSpan)

      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        if (this.pendingClick) {
          this.pushEvent("tag_person", {
            person_id: String(person.id),
            x: this.pendingClick.x,
            y: this.pendingClick.y
          })
        }
      })

      container.appendChild(btn)
    })
  },

  renderCircles(people) {
    this.circlesContainer.replaceChildren()

    people.forEach(pp => {
      const circle = document.createElement("div")
      circle.dataset.circlePersonId = pp.person_id
      circle.className = "absolute w-10 h-10 -ml-5 -mt-5 rounded-full border-2 border-dashed border-white/40 transition-all duration-200 pointer-events-auto"
      circle.style.left = (pp.x * 100) + "%"
      circle.style.top = (pp.y * 100) + "%"

      const tooltip = document.createElement("div")
      tooltip.className = "absolute top-full left-1/2 -translate-x-1/2 mt-1 px-2 py-0.5 bg-black/80 rounded text-xs text-white/80 whitespace-nowrap opacity-0 pointer-events-none tag-tooltip transition-opacity"
      tooltip.textContent = pp.person_name
      circle.appendChild(tooltip)

      circle.addEventListener("mouseenter", () => { tooltip.style.opacity = "1" })
      circle.addEventListener("mouseleave", () => { tooltip.style.opacity = "0" })

      this.circlesContainer.appendChild(circle)
    })
  },

  highlightCircle(personId) {
    const circle = this.circlesContainer.querySelector("[data-circle-person-id='" + personId + "']")
    if (circle) {
      circle.classList.remove("border-white/40")
      circle.classList.add("border-white", "scale-110", "shadow-lg", "shadow-white/20")
      const tooltip = circle.querySelector(".tag-tooltip")
      if (tooltip) tooltip.style.opacity = "1"
    }
  },

  unhighlightCircle(personId) {
    const circle = this.circlesContainer.querySelector("[data-circle-person-id='" + personId + "']")
    if (circle) {
      circle.classList.add("border-white/40")
      circle.classList.remove("border-white", "scale-110", "shadow-lg", "shadow-white/20")
      const tooltip = circle.querySelector(".tag-tooltip")
      if (tooltip) tooltip.style.opacity = "0"
    }
  },

  destroyed() {
    if (this._clickAway) {
      document.removeEventListener("click", this._clickAway)
    }
  }
}

const PersonHighlight = {
  mounted() {
    this.el.addEventListener("mouseenter", () => {
      this.pushEvent("highlight_person_on_photo", { id: this.el.id })
    })

    this.el.addEventListener("mouseleave", () => {
      this.pushEvent("unhighlight_person_on_photo", { id: this.el.id })
    })
  }
}

export { PhotoTagger, PersonHighlight }
