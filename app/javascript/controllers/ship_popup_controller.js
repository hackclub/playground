import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// ship.exe: the pet page's ship button opens it as a modal dialog, and it
// loads the list of what still blocks shipping each time, fresh. The list
// saves each fix itself (see the ship-checks controller). When the popup
// closes after a save, the pet page reloads to show what changed, once every
// save is done.
//
// On the desktop, where this page sits in ship.exe's frame or the pet's own
// window, the button asks the desktop instead, which opens the list in a
// window of its own (see landing.js). Only a page from this site can hear the message.
export default class extends Controller {
  static targets = ["dialog", "body"]
  static values = { url: String, project: Number, name: String }

  connect() {
    this.blank = this.bodyTarget.innerHTML
    this.pending = 0
    this.saved = false
    this.leave = this.leave.bind(this)
    // Turbo keeps a copy of the page it leaves, for Back. The copy must not
    // show the popup open.
    document.addEventListener("turbo:before-cache", this.leave)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.leave)
  }

  async open() {
    if (window.parent !== window) {
      window.parent.postMessage({ type: "playground:ship", action: "open", project: this.projectValue, name: this.nameValue }, location.origin)
      return
    }
    if (this.dialogTarget.open) return
    this.bodyTarget.innerHTML = this.blank
    this.dialogTarget.showModal()
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (!response.ok) throw new Error(response.status)
      Turbo.renderStreamMessage(await response.text())
    } catch {
      this.bodyTarget.querySelector("#ship-checks").textContent = "could not load the checks. close this and try again."
    }
  }

  close() {
    this.save()
    this.dialogTarget.close()
  }

  // Escape and the X close the popup without moving focus off the field
  // being typed in, so its change, and its save, happen here first.
  save() {
    if (this.dialogTarget.contains(document.activeElement)) document.activeElement.blur()
  }

  started() {
    this.pending++
  }

  ended(event) {
    this.pending--
    if (event.detail.ok) this.saved = true
    this.reload()
  }

  changed() {
    this.saved = true
    this.reload()
  }

  closed() {
    this.reload()
  }

  reload() {
    if (this.dialogTarget.open || !this.saved || this.pending > 0 || this.leaving) return
    this.saved = false
    Turbo.visit(location.href, { action: "replace" })
  }

  leave() {
    this.leaving = true
    this.dialogTarget.close()
  }

  // A Tab past either end of the popup wraps around, and never leaves it for
  // the browser's own controls.
  trap(event) {
    if (event.key !== "Tab") return
    const stops = [...this.dialogTarget.querySelectorAll("a[href], button, input, textarea, select, [tabindex]")]
      .filter((el) => !el.disabled && el.tabIndex >= 0 && el.getClientRects().length > 0)
    if (stops.length === 0) return
    const first = stops[0]
    const last = stops[stops.length - 1]
    const at = document.activeElement
    if (event.shiftKey && (at === first || at === this.dialogTarget)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && at === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
