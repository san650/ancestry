const Swipe = {
  mounted() {
    this.startX = 0
    this.startY = 0
    this.startTime = 0
    this.tracking = false

    this.el.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: true })
    this.el.addEventListener("touchmove", this.handleTouchMove.bind(this), { passive: false })
    this.el.addEventListener("touchend", this.handleTouchEnd.bind(this), { passive: true })
  },

  destroyed() {
    // Listeners are cleaned up when element is removed
  },

  handleTouchStart(e) {
    if (e.touches.length !== 1) return
    const touch = e.touches[0]
    this.startX = touch.clientX
    this.startY = touch.clientY
    this.startTime = Date.now()
    this.tracking = true
  },

  handleTouchMove(e) {
    if (!this.tracking || e.touches.length !== 1) return
    const touch = e.touches[0]
    const dx = Math.abs(touch.clientX - this.startX)
    const dy = Math.abs(touch.clientY - this.startY)

    // If horizontal movement is dominant, prevent vertical scroll
    if (dx > dy && dx > 10) {
      e.preventDefault()
    }
  },

  handleTouchEnd(e) {
    if (!this.tracking) return
    this.tracking = false

    const touch = e.changedTouches[0]
    const dx = touch.clientX - this.startX
    const dy = touch.clientY - this.startY
    const elapsed = Date.now() - this.startTime
    const absDx = Math.abs(dx)
    const absDy = Math.abs(dy)

    // Must be primarily horizontal and exceed threshold
    if (absDx < 50 || absDy > absDx * 0.75) return

    // Velocity check: must be fast enough (or far enough)
    const velocity = absDx / elapsed
    if (velocity < 0.3 && absDx < 100) return

    if (dx < 0) {
      this.pushEvent("lightbox_keydown", { key: "ArrowRight" })
    } else {
      this.pushEvent("lightbox_keydown", { key: "ArrowLeft" })
    }
  }
}

export default Swipe
