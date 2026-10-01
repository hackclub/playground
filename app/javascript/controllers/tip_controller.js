import { Controller } from "@hotwired/stimulus"

// A small circled "i" after a step's label. Its tip shows while the mouse is
// on the mark, while the mark has keyboard focus, and after a tap on it.
// Escape, a press anywhere else, a scroll, or moving the mouse away hides it.
// The tip is fixed to the screen, under the mark or above it, so no scrolling
// box around the list cuts it off, in a popup or in a ship window's frame.
// Screen readers hear it as the mark's description.
export default class extends Controller {
  static targets = ["mark", "text"]

  connect() {
    this.hide = this.hide.bind(this)
    this.away = this.away.bind(this)
  }

  disconnect() {
    this.hide()
  }

  enter(event) {
    if (event.pointerType !== "touch") this.show()
  }

  leave(event) {
    if (event.pointerType !== "touch") this.hide()
  }

  show() {
    if (!this.textTarget.hidden) return
    this.textTarget.hidden = false
    this.place()
    document.addEventListener("pointerdown", this.away, true)
    document.addEventListener("keydown", this.away, true)
    document.addEventListener("scroll", this.hide, true)
    window.addEventListener("resize", this.hide)
  }

  hide() {
    if (this.hasTextTarget) this.textTarget.hidden = true
    document.removeEventListener("pointerdown", this.away, true)
    document.removeEventListener("keydown", this.away, true)
    document.removeEventListener("scroll", this.hide, true)
    window.removeEventListener("resize", this.hide)
  }

  // Escape hides the tip before it would close a popup, and the mark keeps
  // its focus. A press outside the mark hides it.
  away(event) {
    if (event.type === "keydown") {
      if (event.key !== "Escape") return
      event.preventDefault()
      event.stopPropagation()
      this.hide()
    } else if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  place() {
    const root = document.documentElement
    const margin = 8
    const text = this.textTarget
    Object.assign(text.style, { left: "0px", top: "0px", maxWidth: `${Math.min(260, root.clientWidth - 2 * margin)}px` })
    const mark = this.markTarget.getBoundingClientRect()
    const box = text.getBoundingClientRect()
    const left = Math.max(margin, Math.min(mark.left, root.clientWidth - margin - box.width))
    const below = mark.bottom + 4
    const top = below + box.height <= root.clientHeight - margin ? below : Math.max(margin, mark.top - 4 - box.height)
    Object.assign(text.style, { left: `${left}px`, top: `${top}px` })
  }
}
