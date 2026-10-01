import { Controller } from "@hotwired/stimulus"

// The guide follows one computer: macOS, Windows, or Linux. It starts on the
// one this browser runs on, or the one picked here before, and the switch
// at its top changes it. Each part that differs, a shortcut or a step,
// names the systems it is for (data-os), and the others hide
// (playground.css). Without this script every version shows, each labelled.
const systems = ["macos", "windows", "linux"]
const store = "playground-guide-os"

export default class extends Controller {
  static targets = ["switch"]

  connect() {
    this.switchTarget.hidden = false
    this.choose(this.saved() ?? this.detected())
  }

  pick(event) {
    this.choose(event.target.value)
    try {
      localStorage.setItem(store, event.target.value)
    } catch {
      // Storage blocked: the choice lasts until the page closes.
    }
  }

  choose(os) {
    this.element.dataset.osCurrent = os
    this.switchTarget.querySelectorAll("input").forEach(input => { input.checked = input.value === os })
  }

  saved() {
    try {
      const os = localStorage.getItem(store)
      return systems.includes(os) ? os : null
    } catch {
      return null
    }
  }

  detected() {
    const platform = navigator.userAgentData?.platform || navigator.userAgent
    if (/win/i.test(platform)) return "windows"
    if (/mac|iphone|ipad/i.test(platform)) return "macos"
    if (/linux|x11|cros|chrome os|android/i.test(platform)) return "linux"
    return "windows"
  }
}
