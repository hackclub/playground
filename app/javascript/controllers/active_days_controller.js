import { Controller } from "@hotwired/stimulus"

// The admin stats chart of people active each day. Each day's bar is a
// button, and the pressed one shows its day's list of who was active, under
// the chart. The page comes with today pressed. The arrow keys, Home, and End
// press the day they move to, and only the pressed day is in the tab order,
// so Tab passes the chart in one stop. On a narrow screen the chart scrolls
// sideways, and it keeps the pressed day in view, today on load.
export default class extends Controller {
  static targets = ["scroller", "day", "list"]

  connect() {
    const pressed = this.dayTargets.find(day => day.getAttribute("aria-pressed") === "true")
    if (pressed) this.reveal(pressed)
  }

  pick({ currentTarget }) { this.press(currentTarget) }

  key(event) {
    const days = this.dayTargets
    const at = days.indexOf(event.currentTarget)
    const to = { ArrowLeft: at - 1, ArrowRight: at + 1, Home: 0, End: days.length - 1 }[event.key]
    if (to === undefined || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
    event.preventDefault()
    const day = days[Math.min(Math.max(to, 0), days.length - 1)]
    this.press(day)
    day.focus({ preventScroll: true })
  }

  press(day) {
    this.dayTargets.forEach(each => {
      each.setAttribute("aria-pressed", each === day)
      each.tabIndex = each === day ? 0 : -1
    })
    this.listTargets.forEach(list => { list.hidden = list.dataset.date !== day.dataset.date })
    this.reveal(day)
  }

  // Scrolls the chart, never the page, just far enough to show the day. The
  // scroller is the days' offset parent, so offsetLeft is from its start.
  reveal(day) {
    if (!this.hasScrollerTarget) return
    const box = this.scrollerTarget
    const left = day.offsetLeft
    const right = left + day.offsetWidth
    if (left < box.scrollLeft) box.scrollLeft = left
    else if (right > box.scrollLeft + box.clientWidth) box.scrollLeft = right - box.clientWidth
  }
}
