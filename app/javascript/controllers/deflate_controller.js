import { Controller } from "@hotwired/stimulus"

// The review page's deflation. The coding buttons fill the approved coding
// hours with a share of the claimed coding, never above the cap. The art
// buttons fill the approved art hours with a share of the claimed art. Art is
// held at its percent of the total, so changing coding moves the art limit
// and lowers the art field when it is over. Values are hours, to the
// hundredth. The reviewer still presses approve, and can type any value.
export default class extends Controller {
  static targets = [ "hours", "art", "artMax", "total", "hold" ]
  static values = { claimed: Number, cap: Number, artClaimed: Number, artPercent: Number }

  set(event) {
    const percent = Number(event.currentTarget.dataset.percent)
    this.hoursTarget.value = Math.min(this.#round(this.claimedValue * percent / 100), this.capValue)
    this.hoursTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.hoursTarget.focus()
  }

  setArt(event) {
    const percent = Number(event.currentTarget.dataset.artPercent)
    this.artTarget.value = this.#round(this.artClaimedValue * percent / 100)
    this.artTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.artTarget.focus()
  }

  changed() { this.#update() }
  changedArt() { this.#update() }

  #update() {
    const coding = Math.min(Number(this.hoursTarget.value) || 0, this.capValue)
    if (!this.hasArtTarget) {
      if (this.hasTotalTarget) this.totalTarget.textContent = this.#round(coding)
      return
    }
    const artMax = this.#round(coding * this.artPercentValue / (100 - this.artPercentValue))
    const allowed = Math.min(this.artClaimedValue, artMax)
    let art = Number(this.artTarget.value) || 0
    const held = art > allowed
    if (held) { art = allowed; this.artTarget.value = allowed }
    this.holdTarget.hidden = !(held || (this.artClaimedValue > artMax && art >= allowed))
    if (this.hasArtMaxTarget) this.artMaxTarget.textContent = artMax
    this.totalTarget.textContent = this.#round(coding + art)
  }

  #round(hours) { return Math.round(hours * 100) / 100 }
}
