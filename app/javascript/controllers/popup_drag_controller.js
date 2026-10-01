import { Controller } from "@hotwired/stimulus"

// A popup drags by its title bar, by mouse, pen, or touch, as the desktop's
// windows drag by their headers. It can go partly off the screen, but at
// least 80px of the title bar, or all of it in a narrower popup, and all of
// its height stay in reach, and past the left edge the X stays in sight too.
// A press on the X closes and never drags. A popup opens where it always
// did: a closed one forgets where it was dragged.
export default class extends Controller {
  static targets = ["head"]

  connect() {
    this.keep = this.keep.bind(this)
    this.reset = this.reset.bind(this)
    window.addEventListener("resize", this.keep)
    this.element.addEventListener("close", this.reset)
  }

  disconnect() {
    window.removeEventListener("resize", this.keep)
    this.element.removeEventListener("close", this.reset)
  }

  start(event) {
    if (!event.isPrimary || event.button !== 0 || event.target.closest("button")) return
    event.preventDefault()
    // From the first press the popup sits where it shows, by its own left
    // and top, in place of its centering.
    const box = this.element.getBoundingClientRect()
    Object.assign(this.element.style, { inset: "auto", margin: "0", transform: "none", left: `${box.left}px`, top: `${box.top}px` })
    this.grab = { pointer: event.pointerId, x: event.clientX - box.left, y: event.clientY - box.top }
    // The capture keeps the pointer's moves and its release, even outside
    // the browser window or the desktop window's frame.
    this.headTarget.setPointerCapture(event.pointerId)
  }

  move(event) {
    if (event.pointerId !== this.grab?.pointer) return
    this.place(event.clientX - this.grab.x, event.clientY - this.grab.y)
  }

  end(event) {
    if (event.pointerId === this.grab?.pointer) this.grab = null
  }

  place(left, top) {
    const root = document.documentElement
    const head = this.headTarget
    const close = head.querySelector("button")
    const grip = Math.min(80, close.offsetLeft - head.offsetLeft)
    left = Math.max(grip - close.offsetLeft, Math.min(left, root.clientWidth - head.offsetLeft - grip))
    top = Math.max(0, Math.min(top, root.clientHeight - head.offsetTop - head.offsetHeight))
    Object.assign(this.element.style, { left: `${left}px`, top: `${top}px` })
  }

  // A dragged popup moves back into reach when the browser window shrinks.
  keep() {
    if (!this.element.open || !this.element.style.left) return
    const box = this.element.getBoundingClientRect()
    this.place(box.left, box.top)
  }

  reset() {
    this.grab = null
    for (const property of ["inset", "margin", "transform", "left", "top"]) this.element.style.removeProperty(property)
  }
}
