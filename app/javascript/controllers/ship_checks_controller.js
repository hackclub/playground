import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// ship.exe's list of what still blocks shipping. Each fix saves on change,
// with no save button: a field when it loses focus or takes Enter, a
// checkbox when it is ticked, a screenshot when it uploads. The list comes
// back and morphs in place, so each step shows at once whether it is done.
//
// The forms post with fetch rather than Turbo Drive, which runs one form at
// a time and would drop a save still on its way when the next one starts.
// The saves go one after another, so the last list drawn is the newest.
export default class extends Controller {
  static targets = ["form"]
  static values = { url: String }

  connect() {
    this.queue = Promise.resolve()
  }

  save(event) {
    const form = event.target.form
    if (form && this.formTargets.includes(form)) form.requestSubmit()
  }

  submit(event) {
    const form = event.target
    if (!this.formTargets.includes(form)) return
    event.preventDefault()
    // Enter commits a field, which also fires its change: one save is enough.
    const body = new FormData(form)
    const sent = new URLSearchParams([...body].filter(([name]) => name.startsWith("project["))).toString()
    if (form.sent === sent) return
    form.sent = sent

    this.dispatch("saving")
    this.queue = this.queue.then(async () => {
      let ok = false
      try {
        const response = await fetch(form.action, { method: "POST", body, headers: { Accept: "text/vnd.turbo-stream.html" } })
        ok = response.ok
        await this.render(response)
      } catch {
        // The list stays as it was, and the next change tries again.
      }
      if (!ok) form.sent = null
      this.dispatch("saved", { detail: { ok } })
    })
  }

  // What is typed or ticked stays as it is when the list morphs. The server
  // sends back what it saved, or the typed value with its error, so a field
  // never needs to change under the participant.
  keep(event) {
    const field = event.target
    if (field.matches("input:not([type=hidden]), textarea") && ["value", "checked"].includes(event.detail.attributeName)) {
      event.preventDefault()
    }
  }

  // The screenshots save by themselves, maybe with uploads still on their
  // way, so the list morphing around them leaves them as they are. Turbo's
  // permanent elements would not do: a stream swaps them for a copy.
  hold(event) {
    if (event.target.id === "ship-screenshot" && event.detail.newElement) event.preventDefault()
  }

  // After an upload, which saves outside the list's forms.
  refresh() {
    const url = new URL(this.urlValue, location.href)
    this.element.querySelectorAll("[data-check]").forEach((item) => url.searchParams.append("shown[]", item.dataset.check))
    this.queue = this.queue.then(async () => {
      try {
        await this.render(await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } }))
      } catch {
        // The upload is saved. The list catches up at the next save.
      }
    })
  }

  async render(response) {
    if (response.headers.get("Content-Type")?.startsWith("text/vnd.turbo-stream.html")) {
      Turbo.renderStreamMessage(await response.text())
    }
  }
}
