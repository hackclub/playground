import { Controller } from "@hotwired/stimulus"

// How long this browser reads Stardance's or the clubs' guide each US
// Eastern day, counted only while the tab shows. The time stays in this
// browser, in localStorage. Once the day's time on the guides passes the
// threshold, it tells the server one more reader read the guide it read most
// that day: the guide and the day, once a day, and nothing else. Without
// localStorage it counts for this page only.
const key = "playground-guide-reading"
let memory = null

export default class extends Controller {
  static values = { guide: String, seconds: Number, url: String }

  connect() {
    this.since = document.hidden ? null : Date.now()
    this.onVisibility = () => (document.hidden ? this.pause() : this.resume())
    this.onHide = () => this.pause()
    document.addEventListener("visibilitychange", this.onVisibility)
    addEventListener("pagehide", this.onHide)
    // Often enough that a reader who closes the tab loses little time, and
    // a short threshold, as tests set, passes soon after it is reached.
    const every = Math.min(5000, Math.max(250, this.secondsValue * 250))
    this.timer = setInterval(() => this.tick(), every)
  }

  disconnect() {
    this.pause()
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
    removeEventListener("pagehide", this.onHide)
  }

  pause() {
    if (this.since === null) return
    this.add(Date.now() - this.since)
    this.since = null
  }

  resume() {
    if (this.since === null) this.since = Date.now()
  }

  tick() {
    if (this.since === null) return
    const now = Date.now()
    this.add(now - this.since)
    this.since = now
  }

  add(ms) {
    const day = easternDay()
    let record = load()
    if (record?.day !== day) record = { day, seconds: {}, sent: false }
    record.seconds[this.guideValue] = (record.seconds[this.guideValue] || 0) + ms / 1000
    save(record)
    const total = Object.values(record.seconds).reduce((sum, each) => sum + each, 0)
    if (!record.sent && !this.sending && total >= this.secondsValue) this.send(record)
  }

  // A failed request tries again on a later tick. One the server turns
  // down, as too many or not today, does not.
  async send(record) {
    this.sending = true
    const guide = Object.entries(record.seconds).sort((a, b) => b[1] - a[1])[0][0]
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
        body: JSON.stringify({ guide, day: record.day }),
        keepalive: true
      })
      if (response.ok || (response.status >= 400 && response.status < 500)) {
        const now = load()
        if (now?.day === record.day) save({ ...now, sent: true })
      }
    } catch {
      // Offline, or the page is going: a later tick, or a later page, sends it.
    } finally {
      this.sending = false
    }
  }
}

// Today's date in US Eastern time, as 2026-10-07.
function easternDay() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date())
}

function load() {
  try {
    return JSON.parse(localStorage.getItem(key))
  } catch {
    return memory
  }
}

function save(record) {
  memory = record
  try {
    localStorage.setItem(key, JSON.stringify(record))
  } catch {
    // Private browsing, or storage turned off: memory keeps it for this page.
  }
}
