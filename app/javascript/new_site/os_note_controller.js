import { Controller } from "@hotwired/stimulus"

// The new site's guide in steps, as os_controller.js does for the one long
// guide. The guide follows one computer: macOS, Windows, or Linux. It starts
// on the one this browser runs on, or the one picked here before. A small
// note under each step that differs names the computer and switches to
// another. Each part that differs, a shortcut or a step, names the systems it
// is for (data-os), and the others hide (playground.css). Without this script
// every version shows, each labelled.
const systems = ["macos", "windows", "linux"]
const store = "playground-guide-os"

export default class extends Controller {
  static targets = ["note"]

  connect() {
    this.noteTargets.forEach(note => { note.hidden = false })
    this.choose(this.saved() ?? this.detected())
  }

  pick(event) {
    const os = event.currentTarget.value
    this.choose(os)
    try {
      localStorage.setItem(store, os)
    } catch {
      // Storage blocked: the choice lasts until the page closes.
    }
  }

  choose(os) {
    this.element.dataset.osCurrent = os
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
