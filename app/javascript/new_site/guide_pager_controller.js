import { Controller } from "@hotwired/stimulus"

// The ways from one step of the guide to another: the buttons under it, its
// list of steps, and the outline. Each lands at the top of the step. Turbo
// opens the step at the top of the page. On a phone the next step and the
// hours stand above the guide, so the page then scrolls down to the guide.
let toTheStep = false

addEventListener("turbo:load", () => {
  if (!toTheStep) return
  toTheStep = false
  const guide = document.getElementById("guide")
  const hub = guide?.closest(".hub")
  if (hub && guide.getBoundingClientRect().top - hub.getBoundingClientRect().top > 40) guide.scrollIntoView({ block: "start" })
})

export default class extends Controller {
  // A click that opens a new tab or window leaves this page as it is.
  go(event) {
    toTheStep = !(event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0)
  }
}
