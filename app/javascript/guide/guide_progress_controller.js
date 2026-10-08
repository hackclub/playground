import { Controller } from "@hotwired/stimulus"
import { touches } from "attribution"
import { EngagementClock, Journey, OPENED, easternDay, reportParams } from "guide_journey"

// How far this browser reads a guide (GuideSections). A section is reached
// when its heading stays in the top two thirds of the screen for a few
// seconds while the tab shows, so a fast scroll past it does not count. At
// the very end of the page, where the last headings cannot scroll that far
// up, anywhere on screen counts. Each section is reported once, ever: the
// ones reported are kept in localStorage, one list a guide. Reports go in
// batches every few seconds, and as a beacon when the page goes. The server
// hears the guide, the day, and the sections, and nothing else.
//
// It also keeps this browser's journey through the guide (journey.js,
// GuideJourneyDay): its engaged time, counted while the tab shows and the
// reader has scrolled, moved the pointer, touched or typed in the last
// idle seconds, and the furthest section it reached. When either moves on
// past a bucket or a section, it tells the server where it was and where
// it is now, with where it came from (attribution.js). The time is kept
// across visits, in this browser alone.
const LOOK_EVERY = 250
const ACTIVITY = ["pointerdown", "pointermove", "keydown", "wheel", "touchstart"]

export default class extends Controller {
  // sections: the guide's sections, by heading anchor. seconds: how long a
  // heading stays in view to count. every: seconds between reports. idle:
  // seconds without activity before time stops counting. minute: seconds a
  // minute of time lasts, which tests shorten.
  static values = { guide: String, sections: Array, seconds: Number, every: Number, url: String,
                    journeyUrl: String, idle: Number, minute: Number }

  connect() {
    this.key = `playground-guide-progress:${this.guideValue}`
    this.reported = new Set(load(this.key))
    this.pending = new Set()
    this.since = new Map()
    this.journey = new Journey(this.guideValue, { stages: [OPENED, ...this.sectionsValue], reach: this.secondsValue, minute: this.minuteValue || 60 })
    this.clock = new EngagementClock({ idle: (this.idleValue || 30) * 1000, now: performance.now(), visible: !document.hidden, active: window.top === window.self })
    this.unsaved = 0
    this.onActivity = () => this.addTime(this.clock.activity(performance.now()))
    ACTIVITY.forEach(name => addEventListener(name, this.onActivity, { passive: true }))
    document.addEventListener("scroll", this.onActivity, { passive: true, capture: true })
    this.looking = setInterval(() => this.look(), LOOK_EVERY)
    this.sending = setInterval(() => this.send(), this.everyValue * 1000)
    this.onHide = () => {
      this.addTime(this.clock.advance(performance.now()))
      this.send(true)
    }
    this.onVisibility = () => {
      if (document.hidden) {
        this.addTime(this.clock.hide(performance.now()))
        this.send(true)
      } else {
        this.addTime(this.clock.show(performance.now()))
      }
    }
    addEventListener("pagehide", this.onHide)
    document.addEventListener("visibilitychange", this.onVisibility)
  }

  disconnect() {
    clearInterval(this.looking)
    clearInterval(this.sending)
    ACTIVITY.forEach(name => removeEventListener(name, this.onActivity))
    document.removeEventListener("scroll", this.onActivity, { capture: true })
    removeEventListener("pagehide", this.onHide)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.addTime(this.clock.advance(performance.now()))
    this.send(true)
  }

  // A hidden tab reads nothing, and starts every heading's time again.
  look() {
    if (document.hidden) return this.since.clear()
    const now = performance.now()
    this.addTime(this.clock.advance(now))
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

  addTime(ms) {
    this.unsaved += ms
  }

  // The engaged time not yet kept goes into the journey's.
  keepTime() {
    const seconds = this.unsaved / 1000
    this.unsaved = 0
    this.journey.addSeconds(seconds)
  }

  // Leaving, the reports go as beacons, which outlive the page.
  send(leaving = false) {
    this.keepTime()
    this.sendSections(leaving)
    this.sendJourney(leaving)
  }

  sendSections(leaving) {
    if (this.pending.size === 0) return
    const sections = [...this.pending]
    this.pending.clear()
    sections.forEach(id => this.reported.add(id))
    save(this.key, [...this.reported])
    const body = withToken(new URLSearchParams({ guide: this.guideValue, day: easternDay() }))
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

  // Where this browser is in its journey, if that moved on since the server
  // last heard. One the server turns down, as too many, is not sent again.
  sendJourney(leaving) {
    if (!this.hasJourneyUrlValue) return
    const report = this.journey.next({ furthest: this.furthest(), touches: touches() })
    if (!report) return
    const body = withToken(new URLSearchParams(reportParams(this.guideValue, report)))
    if (leaving && navigator.sendBeacon?.(this.journeyUrlValue, body)) return
    fetch(this.journeyUrlValue, { method: "POST", body, keepalive: true })
      .then(response => { if (response.status >= 500) this.journey.undo(report) })
      .catch(() => this.journey.undo(report))
  }

  // The index of the furthest section this browser reached, or -1.
  furthest() {
    return Math.max(-1, ...[...this.reported, ...this.pending].map(id => this.sectionsValue.indexOf(id)))
  }
}

function withToken(body) {
  const csrf = document.querySelector("meta[name=csrf-token]")?.content
  if (csrf) body.append(document.querySelector("meta[name=csrf-param]")?.content || "authenticity_token", csrf)
  return body
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
