import { Controller } from "@hotwired/stimulus"

// The active pet switch (active_pets/_switch). Escape, or a click outside
// it, closes its list. Right after a pick, the frame it sits in is drawn
// again with the new pet, and it tells the guide's other steps and the next
// step card to ask again, since they act on the active pet too. Focus comes
// back to the switch, so a keyboard keeps its place.
export default class extends Controller {
  static values = { justSet: Boolean }

  connect() {
    this.outside = event => { if (this.element.open && !this.element.contains(event.target)) this.element.open = false }
    document.addEventListener("click", this.outside)
    if (this.justSetValue) this.announce()
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
  }

  close(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.element.querySelector("summary").focus()
  }

  announce() {
    const frame = this.element.closest("turbo-frame")
    this.element.querySelector("summary").focus({ preventScroll: true })
    document.dispatchEvent(new CustomEvent("guide-step:done", { detail: frame }))
    const card = document.getElementById("hub-next")
    if (card && card !== frame) reload(card)
  }
}

// A frame drawn with its page loads from its data-src the first time.
function reload(frame) {
  if (frame.src) frame.reload()
  else if (frame.dataset.src) frame.src = frame.dataset.src
}
