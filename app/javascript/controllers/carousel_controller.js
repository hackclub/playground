import { Controller } from "@hotwired/stimulus"

// A pet's screenshots, one at a time. The arrows step through them and wrap
// around, a dot goes straight to one, a swipe on touch steps, and the arrow
// keys step once the carousel has focus. The screenshot shown is announced.
// Nothing moves by itself.
//
// The arrows' strips and the dots sit on the screenshot shown, which may be
// smaller than the carousel when the screenshots differ in shape, so each
// change of screenshot or size places them on it again.
export default class extends Controller {
  static targets = ["slides", "slide", "dot", "status"]

  connect() {
    this.index = 0
    this.place()
  }

  previous() { if (!this.swiped) this.show(this.index - 1) }
  next() { if (!this.swiped) this.show(this.index + 1) }
  go({ params: { index } }) { this.show(index) }

  key(event) {
    const to = { ArrowLeft: this.index - 1, ArrowRight: this.index + 1, Home: 0, End: this.slideTargets.length - 1 }[event.key]
    if (to === undefined || event.altKey || event.ctrlKey || event.metaKey) return
    event.preventDefault()
    this.show(to)
  }

  // A finger or pen that moves mostly sideways by 40px or more steps. A
  // swipe that ends on an arrow's strip steps once, not again for its tap.
  press(event) {
    this.start = event.pointerType === "mouse" ? null : { x: event.clientX, y: event.clientY }
  }

  release(event) {
    if (!this.start || event.type === "pointercancel") return (this.start = null)
    const dx = event.clientX - this.start.x
    const dy = event.clientY - this.start.y
    this.start = null
    if (Math.abs(dx) < 40 || Math.abs(dx) <= Math.abs(dy)) return
    this.show(this.index + (dx < 0 ? 1 : -1))
    this.swiped = true
    setTimeout(() => { this.swiped = false }, 350)
  }

  show(index) {
    const count = this.slideTargets.length
    this.index = (index + count) % count
    this.slideTargets.forEach((slide, i) => mark(slide, "aria-hidden", i !== this.index))
    this.dotTargets.forEach((dot, i) => mark(dot, "aria-current", i === this.index))
    this.statusTarget.textContent = `screenshot ${this.index + 1} of ${count}`
    this.place()
  }

  place() {
    const slide = this.slideTargets[this.index]
    const box = this.slidesTarget.style
    box.setProperty("--shot-left", `${slide.offsetLeft}px`)
    box.setProperty("--shot-top", `${slide.offsetTop}px`)
    box.setProperty("--shot-width", `${slide.offsetWidth}px`)
    box.setProperty("--shot-height", `${slide.offsetHeight}px`)
  }
}

function mark(element, attribute, on) {
  if (on) element.setAttribute(attribute, "true")
  else element.removeAttribute(attribute)
}
