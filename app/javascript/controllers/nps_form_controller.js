import { Controller } from "@hotwired/stimulus"

// The NPS questions. The send button of the form around them stays off
// until a score is picked and each required answer holds more than spaces,
// and the hint says so meanwhile. The server checks again.
//
// In the ship list the questions fix a step, and the list morphs in place
// after each save, which turns the button back on, so it is checked again
// after a morph.
export default class extends Controller {
  static targets = ["hint"]

  connect() {
    this.check()
  }

  check() {
    const form = this.element.closest("form")
    if (!form) return
    const scored = !!this.element.querySelector("input[type=radio]:checked")
    const answered = [...this.element.querySelectorAll("textarea[required]")].every(field => field.value.trim() !== "")
    const ready = scored && answered
    form.querySelectorAll("button[type=submit], input[type=submit]").forEach(button => { button.disabled = !ready })
    this.hintTargets.forEach(hint => { hint.hidden = ready })
  }

  // A morph reports each element it changes, so one check follows them all.
  checkSoon() {
    if (this.pending) return
    this.pending = requestAnimationFrame(() => {
      this.pending = null
      if (this.element.isConnected) this.check()
    })
  }

  disconnect() {
    if (this.pending) cancelAnimationFrame(this.pending)
    this.pending = null
  }
}
