import { Controller } from "@hotwired/stimulus"

// The delete button opens three popups at once, stacked like a pile of error
// dialogs, the first on top. A confirmed popup closes, and the last one to
// close submits the delete form, so the server does what it always did. A
// cancel, an X, or Escape closes every popup and deletes nothing.
//
// The popups are dialogs opened with show(), not showModal(), because a modal
// dialog makes the dialogs under it inert, and here all three take clicks.
// The rest of the page goes inert instead, so it takes no clicks, no focus,
// and no screen reader visits, and Tab cycles through the popups.
//
// On the desktop's trash page (desktop), the popups open at once over the
// desktop, and the desktop hears whether the pet was deleted or kept. The
// delete goes by fetch, so the page never leaves, and a pet that cannot go
// counts as kept. Only a page from this site can hear the message.
export default class extends Controller {
  static targets = ["form", "button", "popup"]
  static values = { desktop: Boolean, project: Number }

  connect() {
    this.close = this.close.bind(this)
    this.onKey = this.onKey.bind(this)
    this.onPress = this.onPress.bind(this)
    // Turbo keeps a copy of the page it leaves, for Back. The copy must not
    // show open popups over an inert page.
    document.addEventListener("turbo:before-cache", this.close)
    if (this.desktopValue) this.open()
  }

  disconnect() {
    this.close()
    document.removeEventListener("turbo:before-cache", this.close)
  }

  open() {
    if (this.blocked) return
    this.blocked = this.hasFormTarget ? [this.formTarget] : []
    for (let el = this.element; el !== document.body; el = el.parentElement) {
      for (const sibling of el.parentElement.children) if (sibling !== el) this.blocked.push(sibling)
    }
    this.blocked = this.blocked.filter((el) => !el.inert)
    this.blocked.forEach((el) => (el.inert = true))

    this.popupTargets.forEach((popup) => popup.show())
    this.popupTargets.reverse().forEach((popup) => this.bringToFront(popup))
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("mousedown", this.onPress)
    this.focus(this.stack[0])
  }

  confirm(event) {
    const popup = event.currentTarget.closest("dialog")
    // Closing a dialog gives focus back to the popup that had it before, and
    // focus raises a popup, so the next one is picked before this one closes.
    const next = this.stack.find((other) => other !== popup)
    popup.close()
    if (next) return this.focus(next)
    this.close()
    if (this.desktopValue) return this.remove()
    this.formTarget.requestSubmit(this.buttonTarget)
  }

  cancel() {
    if (!this.blocked) return
    this.close()
    if (this.desktopValue) return this.tell("kept")
    this.buttonTarget.focus()
  }

  async remove() {
    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST", body: new FormData(this.formTarget), headers: { Accept: "application/json" }
      })
      this.tell(response.ok ? "deleted" : "kept")
    } catch {
      this.tell("kept")
    }
  }

  tell(action) {
    window.parent.postMessage({ type: "playground:trash", action, project: this.projectValue }, location.origin)
  }

  close() {
    if (!this.blocked) return
    this.popupTargets.forEach((popup) => popup.close())
    this.blocked.forEach((el) => (el.inert = false))
    this.blocked = null
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("mousedown", this.onPress)
  }

  // A press or focus raises a popup above the others, as on the desktop.
  raise(event) {
    this.bringToFront(event.currentTarget)
  }

  bringToFront(popup) {
    const others = this.openPopups.filter((other) => other !== popup)
    others.sort((a, b) => Number(a.style.zIndex) - Number(b.style.zIndex))
    others.concat(popup).forEach((other, i) => (other.style.zIndex = 10 + i))
  }

  // The safe choice, as in each popup's autofocus.
  focus(popup) {
    popup.querySelector("[autofocus]").focus()
  }

  onKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    } else if (event.key === "Tab") {
      // Inside a desktop window, a Tab past the last popup would leave the frame.
      event.preventDefault()
      const stops = this.openPopups.flatMap((popup) => [...popup.querySelectorAll("button")])
      const at = stops.indexOf(document.activeElement)
      const next = event.shiftKey ? (at <= 0 ? stops.length : at) - 1 : (at + 1) % stops.length
      stops[next].focus()
    }
  }

  // A press on the page behind does nothing, and focus stays in the popups.
  onPress(event) {
    if (!event.target.closest?.("dialog.popup")) event.preventDefault()
  }

  get openPopups() {
    return this.popupTargets.filter((popup) => popup.open)
  }

  // The open popups, top first.
  get stack() {
    return this.openPopups.sort((a, b) => Number(b.style.zIndex) - Number(a.style.zIndex))
  }
}
