// A browser's journey through one guide (GuideJourneyDay), kept in this
// browser alone: the US Eastern day it started, its first and last touch
// then (attribution.js), its engaged time, and the furthest point it has
// told the server of. The guide's tracker (guide_progress_controller.js)
// drives it.

// The time buckets, in minutes. The server knows the same.
export const MINUTES = [0, 2, 5, 10, 20, 40, 60]
export const OPENED = "opened"

// Engaged time: while the tab shows and the reader scrolled, moved the
// pointer, touched or typed within the last idle ms. A page that opens in
// view, and a tab that comes back into view, count as activity, except
// inside the desktop's windows (active: false), where the desktop may
// reopen the guide unread: there only the reader's own activity counts.
// Each call takes the time now, and returns the engaged ms since the call
// before.
export class EngagementClock {
  constructor({ idle, now, visible = true, active = true }) {
    this.idle = idle
    this.last = now
    this.visible = visible
    this.framed = !active
    this.activeAt = visible && active ? now : -Infinity
  }

  advance(now) {
    const ms = this.visible ? Math.max(0, Math.min(now, this.activeAt + this.idle) - this.last) : 0
    this.last = Math.max(this.last, now)
    return ms
  }

  activity(now) {
    const ms = this.advance(now)
    if (this.visible) this.activeAt = now
    return ms
  }

  show(now) {
    const ms = this.advance(now)
    this.visible = true
    if (!this.framed) this.activeAt = now
    return ms
  }

  hide(now) {
    const ms = this.advance(now)
    this.visible = false
    return ms
  }
}

// The bucket a time falls in, as its minutes. minute: seconds a minute
// lasts, which tests shorten.
export function bucket(seconds, minute = 60) {
  return MINUTES.filter(minutes => seconds >= minutes * minute).pop()
}

// Today in US Eastern time, as 2026-10-07.
export function easternDay(date = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).format(date)
}

// One guide's journey in localStorage. Without storage it does nothing:
// with nothing to remember what it already said, every page would count
// the reader again.
export class Journey {
  // stages: "opened" then the guide's sections, in order. reach: seconds of
  // engaged time that open the guide even before a section is reached.
  constructor(guide, { stages, reach, minute, storage = localStorageOrNull() }) {
    this.key = `playground-guide-journey:${guide}`
    this.stages = stages
    this.reach = reach
    this.minute = minute
    this.storage = storage
  }

  load() {
    if (!this.storage) return null
    try {
      const state = JSON.parse(this.storage.getItem(this.key))
      return state && typeof state === "object" ? state : { seconds: 0 }
    } catch {
      return null
    }
  }

  save(state) {
    if (!this.storage) return false
    try {
      this.storage.setItem(this.key, JSON.stringify(state))
      return true
    } catch {
      return false
    }
  }

  // Adds engaged time, read fresh, so two tabs each add their own.
  addSeconds(seconds) {
    if (!(seconds > 0)) return
    const state = this.load()
    if (state) this.save({ ...state, seconds: (Number(state.seconds) || 0) + seconds })
  }

  // The report to send now, or null: where the server last heard this
  // browser was, and where it is now. furthest: the index of the furthest
  // section reached, or -1. touches: { first, last }, kept from the start.
  // It is marked sent at once, and undo puts it back if it fails.
  next({ furthest, touches, day = easternDay() }) {
    const state = this.load()
    if (!state) return null
    const seconds = Number(state.seconds) || 0
    if (!state.day && seconds < this.reach && furthest < 0) return null
    if (!state.day) Object.assign(state, { day, first: touches.first, last: touches.last })
    const was = state.sent ? [this.stages.indexOf(state.sent.stage), MINUTES.indexOf(state.sent.minutes)] : [-1, -1]
    // A stage the guide no longer has: stop, rather than count again.
    if (was[0] === -1 && state.sent) return null
    const now = [Math.max(furthest + 1, was[0], 0), Math.max(MINUTES.indexOf(bucket(seconds, this.minute)), was[1], 0)]
    if (now[0] === was[0] && now[1] === was[1]) return null
    const to = { stage: this.stages[now[0]], minutes: MINUTES[now[1]] }
    const report = { day: state.day, first: state.first, last: state.last, from: state.sent || null, to }
    if (!this.save({ ...state, sent: to })) return null
    return report
  }

  // A report that did not arrive: the server still has it where it was.
  undo(report) {
    const state = this.load()
    if (state?.sent?.stage === report.to.stage && state.sent.minutes === report.to.minutes) this.save({ ...state, sent: report.from })
  }
}

// Reading localStorage itself throws where storage is blocked.
function localStorageOrNull() {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

// A report as the parameters the server reads.
export function reportParams(guide, report) {
  const params = { guide, day: report.day, to_stage: report.to.stage, to_minutes: String(report.to.minutes) }
  if (report.from) Object.assign(params, { from_stage: report.from.stage, from_minutes: String(report.from.minutes) })
  for (const [prefix, touch] of [["first", report.first], ["last", report.last]]) {
    for (const field of ["source", "medium", "campaign"]) params[`${prefix}_${field}`] = touch?.[field] || ""
  }
  return params
}
