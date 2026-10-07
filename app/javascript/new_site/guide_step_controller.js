import { Controller } from "@hotwired/stimulus"

// A guide step's frame. While it waits on Hackatime it asks again every few
// seconds, and only while the guide shows. A step just done tells the other
// steps, which ask again, as one may wait on it, and the parts beside the
// guide, whose next step, hours, and pets may change with it. A link to a step lands on it,
// though the steps above load after the page.
export default class extends Controller {
  static values = { every: Number }

  connect() {
    this.frame = this.element.closest("turbo-frame")
    this.landIfLinked()
    this.onDone = event => { if (event.detail !== this.frame) reload(this.frame) }
    document.addEventListener("guide-step:done", this.onDone)
    if (this.element.querySelector(".just-done")) this.announceDone()
    if (this.everyValue > 0) this.timer = setTimeout(() => this.askAgain(), this.everyValue * 1000)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("guide-step:done", this.onDone)
    if (this.whenShown) document.removeEventListener("visibilitychange", this.whenShown)
  }

  announceDone() {
    document.dispatchEvent(new CustomEvent("guide-step:done", { detail: this.frame }))
    for (const id of ["hub-next", "hub-side"]) {
      const part = document.getElementById(id)
      if (part) reload(part)
    }
  }

  // A guide out of sight, in a hidden tab, waits to ask until it shows again.
  askAgain() {
    if (!document.hidden) return this.frame.reload()
    this.whenShown = () => {
      if (document.hidden) return
      document.removeEventListener("visibilitychange", this.whenShown)
      this.frame.reload()
    }
    document.addEventListener("visibilitychange", this.whenShown)
  }

  // Each step that loads soon after the page puts the linked one back in
  // view, since a step above it pushes it down as it fills.
  landIfLinked() {
    const linked = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)))
    if (linked && performance.now() < 5000) linked.scrollIntoView({ block: "start" })
  }
}

// A frame drawn with its page loads from its data-src the first time.
function reload(frame) {
  if (frame.src) frame.reload()
  else if (frame.dataset.src) frame.src = frame.dataset.src
}
