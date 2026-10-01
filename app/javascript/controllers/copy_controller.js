import { Controller } from "@hotwired/stimulus"

// One copy button per address line, plus copy-all (flavortown's feature,
// with the copy-all it lacked), and one per way to reach the participant.
// A shortcut clicks the button, so it says "copied ✓" too.
export default class extends Controller {
  copy(event) {
    const button = event.currentTarget
    navigator.clipboard.writeText(button.dataset.copy).then(() => {
      // A second press while it says so keeps the label it had first.
      button.dataset.label ??= button.textContent
      button.textContent = "copied ✓"
      clearTimeout(button.copiedTimer)
      button.copiedTimer = setTimeout(() => (button.textContent = button.dataset.label), 1500)
    })
  }
}
