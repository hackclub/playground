import { Controller } from "@hotwired/stimulus"

// The review page's deflation presets. A button fills the approved hours with
// its share of the claimed hours, to the hundredth of an hour. The reviewer
// still presses approve, and can type any value.
export default class extends Controller {
  static targets = [ "hours" ]
  static values = { claimed: Number }

  set(event) {
    const percent = Number(event.currentTarget.dataset.percent)
    this.hoursTarget.value = Math.round(this.claimedValue * percent) / 100
    this.hoursTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.hoursTarget.focus()
  }
}
