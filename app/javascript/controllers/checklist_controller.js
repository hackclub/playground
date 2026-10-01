import { Controller } from "@hotwired/stimulus"

// Saves each checklist tick as it happens.
export default class extends Controller {
  static values = { url: String }

  save(event) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams({ key: event.target.name, value: event.target.checked ? "1" : "0" })
    fetch(this.urlValue, { method: "PATCH", body, headers: { "X-CSRF-Token": token } })
  }
}
