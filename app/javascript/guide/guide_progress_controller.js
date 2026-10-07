import { Controller } from "@hotwired/stimulus"

// How far this browser reads a guide (GuideSections). A section is reached
// when its heading stays in the top two thirds of the screen for a few
// seconds while the tab shows, so a fast scroll past it does not count. At
// the very end of the page, where the last headings cannot scroll that far
// up, anywhere on screen counts. Each section is reported once, ever: the
// ones reported are kept in localStorage, one list a guide. Reports go in
// batches every few seconds, and as a beacon when the page goes. The server
// hears the guide, the day, and the sections, and nothing else.
const LOOK_EVERY = 250

export default class extends Controller {
  // sections: the guide's sections, by heading anchor. seconds: how long a
  // heading stays in view to count. every: seconds between reports.
  static values = { guide: String, sections: Array, seconds: Number, every: Number, url: String }

  connect() {
    this.key = `playground-guide-progress:${this.guideValue}`
    this.reported = new Set(load(this.key))
    this.pending = new Set()
    this.since = new Map()
    this.looking = setInterval(() => this.look(), LOOK_EVERY)
    this.sending = setInterval(() => this.send(), this.everyValue * 1000)
    this.onHide = () => this.send(true)
    this.onVisibility = () => { if (document.hidden) this.send(true) }
    addEventListener("pagehide", this.onHide)
    document.addEventListener("visibilitychange", this.onVisibility)
  }

  disconnect() {
    clearInterval(this.looking)
    clearInterval(this.sending)
    removeEventListener("pagehide", this.onHide)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.send(true)
  }

  // A hidden tab reads nothing, and starts every heading's time again.
  look() {
    if (document.hidden) return this.since.clear()
    const now = performance.now()
    const atEnd = innerHeight + scrollY >= document.documentElement.scrollHeight - 2
    const line = atEnd ? innerHeight : innerHeight * 2 / 3
    for (const id of this.sectionsValue) {
      if (this.reported.has(id) || this.pending.has(id)) continue
      const box = document.getElementById(id)?.getBoundingClientRect()
      if (!box || box.height === 0 || box.bottom <= 0 || box.top >= line) {
        this.since.delete(id)
      } else if (!this.since.has(id)) {
        this.since.set(id, now)
      } else if (now - this.since.get(id) >= this.secondsValue * 1000) {
        this.since.delete(id)
        this.pending.add(id)
      }
    }
  }

  // Leaving, the report goes as a beacon, which outlives the page.
  send(leaving = false) {
    if (this.pending.size === 0) return
    const sections = [...this.pending]
    this.pending.clear()
    sections.forEach(id => this.reported.add(id))
    save(this.key, [...this.reported])
    const body = new URLSearchParams({ guide: this.guideValue, day: easternDay() })
    const csrf = document.querySelector("meta[name=csrf-token]")?.content
    if (csrf) body.append(document.querySelector("meta[name=csrf-param]")?.content || "authenticity_token", csrf)
    sections.forEach(id => body.append("sections[]", id))
    if (leaving && navigator.sendBeacon?.(this.urlValue, body)) return
    fetch(this.urlValue, { method: "POST", body, keepalive: true })
      .then(response => { if (response.status >= 500) this.retry(sections) })
      .catch(() => this.retry(sections))
  }

  // A report that did not arrive goes again with the next.
  retry(sections) {
    sections.forEach(id => {
      this.reported.delete(id)
      this.pending.add(id)
    })
    save(this.key, [...this.reported])
  }
}

// Today's date in US Eastern time, as 2026-10-07.
function easternDay() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date())
}

function load(key) {
  try {
    const sections = JSON.parse(localStorage.getItem(key))
    return Array.isArray(sections) ? sections : []
  } catch {
    return []
  }
}

function save(key, sections) {
  try {
    localStorage.setItem(key, JSON.stringify(sections))
  } catch {
    // Private browsing, or storage turned off: this page still reports each section once.
  }
}
