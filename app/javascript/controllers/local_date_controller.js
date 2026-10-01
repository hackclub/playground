import { Controller } from "@hotwired/stimulus"

// Shows a <time> as a date in the viewer's own format and time zone, such as
// "Sep 23, 2026" or "23.09.2026". The text starts as the ISO date, which stays
// if scripts don't run. It is rebuilt from the datetime attribute each time,
// so a page that Turbo redraws or restores from its cache shows the same text.
export default class extends Controller {
  connect() {
    const date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(date)) return
    this.element.textContent = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(date)
  }
}
