import { Controller } from "@hotwired/stimulus"

// A link to the old desktop opens the question in its window
// (shared/_classic_dialog) instead of its page. Without this script, or
// without the window, the link goes to the page that asks.
export default class extends Controller {
  open(event) {
    const dialog = document.getElementById("classic-dialog")
    if (!dialog?.showModal) return
    event.preventDefault()
    dialog.showModal()
  }
}
