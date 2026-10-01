import { Controller } from "@hotwired/stimulus"

// Keeps this admin's claim on the item alive. If someone else takes it, the
// banner shows instead of letting the admin keep typing into a lost claim.
export default class extends Controller {
  static values = { url: String, type: String, id: Number, stage: String }
  static targets = ["banner"]

  connect() {
    this.timer = setInterval(() => this.beat(), 30000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async beat() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams({ type: this.typeValue, id: this.idValue, stage: this.stageValue })
    const res = await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "application/json" } })
    if (!res.ok) return
    const data = await res.json()
    if (!data.ok && this.hasBannerTarget) {
      this.bannerTarget.hidden = false
      this.bannerTarget.querySelector("[data-holder]").textContent = data.holder
    }
  }
}
