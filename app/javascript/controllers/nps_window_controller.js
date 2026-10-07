import { Controller } from "@hotwired/stimulus"
import { confetti } from "confetti"

// nps.exe's page. In its window on the desktop, cancel asks the desktop to
// close the window, which skips the form for 12 hours, and a sent answer
// asks it to close the window with confetti (see landing.js). Only the
// desktop that holds the page hears it. In a tab of its own, cancel is a
// link to the desktop, and the confetti falls over the page.
export default class extends Controller {
  connect() {
    this.sent = this.sent.bind(this)
    this.element.addEventListener("turbo:submit-end", this.sent)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.sent)
  }

  close(event) {
    if (!this.framed) return
    event.preventDefault()
    this.tell("close")
  }

  sent(event) {
    if (!event.detail.success) return
    if (this.framed) this.tell("sent")
    else confetti()
  }

  get framed() {
    return window.parent !== window
  }

  tell(action) {
    window.parent.postMessage({ type: "playground:nps", action }, location.origin)
  }
}
