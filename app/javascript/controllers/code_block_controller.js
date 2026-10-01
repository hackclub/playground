import { Controller } from "@hotwired/stimulus"

// A code block's copy button puts its code on the clipboard, less the faded
// lines that only show where it goes. Where the clipboard is out of reach,
// the code is selected instead, ready to copy by hand.
export default class extends Controller {
  static targets = ["code", "button"]

  // The button does nothing without this script, so it hides until it runs.
  connect() {
    this.buttonTarget.hidden = false
  }

  copy() {
    const lines = [...this.codeTarget.querySelectorAll(".line:not(.context)")]
    const text = lines.map(line => line.textContent).join("\n")
    const write = navigator.clipboard?.writeText(text) ?? Promise.reject(new Error("no clipboard"))
    write.then(() => this.say("copied ✓"), () => {
      const range = document.createRange()
      range.setStartBefore(lines[0])
      range.setEndAfter(lines[lines.length - 1])
      getSelection().removeAllRanges()
      getSelection().addRange(range)
      this.say("selected, copy it by hand")
    })
  }

  say(text) {
    this.buttonTarget.textContent = text
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.buttonTarget.textContent = "copy"), 1500)
  }
}
