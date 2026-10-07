import { Controller } from "@hotwired/stimulus"

// The next step card hides while the part of the guide it points to is on
// screen, since the reader is already there. It points to a part of one of
// the guide's steps, and only that step's page holds the part. A heading
// stands for its whole section. A card that points to another step, or to
// another page, always shows.
//
// The server knows the account, and this browser knows how far the reader
// has read (guide_place_controller.js). A step that comes from reading
// (progress) never sends the reader back: once they have read past where it
// points, it says continue, on to the furthest step they read, or, on that
// step, leaves out its link. A step can say something else once the reader
// has read past the part it names without doing it (later).
export default class extends Controller {
  static targets = ["link", "title", "detail"]
  static values = { place: String, steps: Array, progress: Object, later: Object }

  connect() {
    this.followPlace()
    if (!this.hasLinkTarget) return
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

  followPlace() {
    if (!this.hasLinkTarget) return
    const place = readPlace(this.placeValue)
    const furthest = this.stepsValue.findIndex(([slug]) => slug === place?.furthest)
    const later = this.laterValue
    if (later.href && furthest > this.stepOf(later.href)) return this.say(later)

    const progress = this.progressValue
    if (!progress.title) return
    if (furthest > this.stepOf(this.linkTarget.getAttribute("href"))) {
      const [, name, path] = this.stepsValue[furthest]
      this.say({ ...progress, href: path, action: `continue: ${name}` })
    }
    // On the step it would go on to, there is nowhere to go on to.
    const { pathname, hash } = new URL(this.linkTarget.href)
    if (!hash && pathname === location.pathname) this.linkTarget.remove()
  }

  say({ title, detail, href, action }) {
    if (title) this.titleTarget.textContent = title
    if (detail) this.detailTarget.textContent = detail
    this.linkTarget.setAttribute("href", href)
    this.linkTarget.textContent = action
  }

  // The index of the step whose page an address is, or -1.
  stepOf(href) {
    const { pathname } = new URL(href, location.href)
    return this.stepsValue.findIndex(([, , path]) => path === pathname)
  }
}

function readPlace(key) {
  try {
    return JSON.parse(localStorage.getItem(key))
  } catch {
    return null
  }
}
