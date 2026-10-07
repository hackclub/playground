import { Controller } from "@hotwired/stimulus"

// The next step card hides while the part of the guide it points to is on
// screen, since the reader is already there. It points to a part of one of
// the guide's steps, and only that step's page holds the part. A heading
// stands for its whole section. A card that points to another step, or to
// another page, always shows.
export default class extends Controller {
  static targets = ["link"]

  connect() {
    const { hash } = new URL(this.linkTarget.getAttribute("href"), location.href)
    const spot = hash && document.getElementById(decodeURIComponent(hash.slice(1)))
    if (!spot) return
    const area = /^H[1-6]$/.test(spot.tagName) ? (spot.closest("section") ?? spot) : spot
    this.observer = new IntersectionObserver(([entry]) => { this.element.hidden = entry.isIntersecting })
    this.observer.observe(area)
  }

  disconnect() {
    this.observer?.disconnect()
    this.element.hidden = false
  }
}
