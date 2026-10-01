import { Controller } from "@hotwired/stimulus"

// Single-key shortcuts for the admin screens. Any element with
// data-shortcut="x" is clicked (or focused, for inputs) when x is pressed
// outside a text field. data-shortcut-confirm needs two presses within 1.5 s,
// for verdicts that end a stage. Ctrl+Enter works inside text fields too.
export default class extends Controller {
  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  onKey(event) {
    if (event.metaKey || event.altKey) return
    const typing = event.target.closest("input, textarea, select")
    let key = event.key.toLowerCase()
    if (event.ctrlKey && key === "enter") key = "ctrl+enter"
    else if (typing || event.ctrlKey) return

    const el = this.element.querySelector(`[data-shortcut="${CSS.escape(key)}"]`)
    if (!el || el.disabled) return
    event.preventDefault()

    if (el.matches("input, textarea, select")) return el.focus()
    if ("shortcutConfirm" in el.dataset && this.armed !== el) {
      this.arm(el)
      return
    }
    this.disarm()
    el.click()
  }

  arm(el) {
    this.disarm()
    this.armed = el
    el.classList.add("armed")
    this.armTimer = setTimeout(() => this.disarm(), 1500)
  }

  disarm() {
    if (this.armed) this.armed.classList.remove("armed")
    this.armed = null
    clearTimeout(this.armTimer)
  }
}
