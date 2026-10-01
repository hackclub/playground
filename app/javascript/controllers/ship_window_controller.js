import { Controller } from "@hotwired/stimulus"

// The ship list's own page, when it fills a pet's ship window on the
// desktop, tells the desktop what happens in it: a save starts, a save ends,
// a screenshot uploads, or the pet ships. From that the desktop reloads the
// pet page that asked (see landing.js). Only a page from this site hears
// it, and the page listens only to the desktop that holds it. In a tab of
// its own, it tells nobody.
export default class extends Controller {
  connect() {
    this.listen = this.listen.bind(this)
    window.addEventListener("message", this.listen)
  }

  disconnect() {
    window.removeEventListener("message", this.listen)
  }

  saving() {
    this.tell("saving")
  }

  saved(event) {
    this.tell("saved", { ok: event.detail.ok })
  }

  changed() {
    this.tell("changed")
  }

  submitted(event) {
    if (event.detail.success && event.target.matches("form[action$='/ship']")) this.tell("shipped")
  }

  // The window's X asks first, so a field still being typed in lets go of
  // its focus, and its change saves.
  listen(event) {
    if (event.source !== window.parent || event.origin !== location.origin || event.data?.type !== "playground:ship") return
    if (event.data.action === "close" && this.element.contains(document.activeElement)) document.activeElement.blur()
  }

  tell(action, detail = {}) {
    if (window.parent !== window) window.parent.postMessage({ type: "playground:ship", action, ...detail }, location.origin)
  }
}
