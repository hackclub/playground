import { Controller } from "@hotwired/stimulus"

// The reader's place in a guide, kept in this browser alone, in
// localStorage: the step they read last, and the furthest step they reached.
// Each guide keeps its own: the new site's, Stardance's, and the clubs'.
// The guide's bare address opens at the step read last (guides/_reopen), and
// the next step card never sends the reader back behind the furthest
// (next_step_controller.js). Without localStorage, nothing is kept.
export default class extends Controller {
  // steps: each step's slug, in order. step: this page's.
  static values = { key: String, steps: Array, step: String, path: String }

  connect() {
    const steps = this.stepsValue
    const at = steps.indexOf(this.stepValue)
    if (at < 0) return
    let place = null
    try {
      place = JSON.parse(localStorage.getItem(this.keyValue))
    } catch {
      // Unreadable: start again from this step.
    }
    const furthest = Math.max(at, steps.indexOf(place?.furthest))
    // The first step is the bare address's own, so it needs no way back.
    const record = { last: this.stepValue, path: at > 0 ? this.pathValue : null, furthest: steps[furthest] }
    try {
      localStorage.setItem(this.keyValue, JSON.stringify(record))
    } catch {
      // Private browsing, or storage turned off: the guide opens at its first step.
    }
  }
}
