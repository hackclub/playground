import { Controller } from "@hotwired/stimulus"

// The guide's outline, like the one beside a Google Doc. The page lists the
// guide's steps, and this lists the step that shows: each of its headings, a
// heading under another set in. A click goes to the heading and marks it,
// until the reader scrolls, and so does a link to a part of the step. The
// heading being read is marked as the page scrolls. The headings that name a
// computer are left out.
export default class extends Controller {
  static targets = ["sections"]
  static values = { article: String }

  connect() {
    this.article = document.querySelector(this.articleValue)
    if (!this.article || !this.hasSectionsTarget) return
    this.build()
    this.onScroll = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => { this.frame = null; this.mark() })
    }
    addEventListener("scroll", this.onScroll, { passive: true })
    // A scroll of the reader's own lets go of a heading picked here.
    this.onReader = () => { this.picked = null }
    for (const type of ["wheel", "touchmove", "keydown", "mousedown"]) addEventListener(type, this.onReader, { passive: true })
    // The computer switch hides and shows headings.
    this.onChange = () => setTimeout(() => this.build(), 0)
    this.article.addEventListener("change", this.onChange)
  }

  disconnect() {
    removeEventListener("scroll", this.onScroll)
    for (const type of ["wheel", "touchmove", "keydown", "mousedown"]) removeEventListener(type, this.onReader)
    this.article?.removeEventListener("change", this.onChange)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  build() {
    this.headings = [...this.article.querySelectorAll(".guide-step h2, .guide-step h3")]
      .filter(h => !h.closest(".os-step") && h.offsetParent !== null)
    const items = this.headings.map(heading => {
      heading.id ||= slug(heading.textContent)
      const item = document.createElement("li")
      item.className = `outline-${heading.tagName.toLowerCase()}`
      const link = Object.assign(document.createElement("a"), { href: `#${heading.id}`, textContent: heading.textContent.trim() })
      link.addEventListener("click", event => {
        event.preventDefault()
        heading.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
        history.replaceState(history.state, "", `#${heading.id}`)
        // The mousedown of this click has passed, so the pick holds.
        this.picked = heading
        this.mark()
      })
      item.append(link)
      return item
    })
    this.sectionsTarget.replaceChildren(...items)
    this.links = items.map(item => item.firstChild)
    this.picked ??= this.linkedHeading()
    this.mark()
  }

  // The heading of the part the address links to, such as #pick-step, a
  // step inside the section "Pick your pet's project".
  linkedHeading() {
    const spot = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)))
    if (!spot || !this.article.contains(spot)) return null
    return this.headings.includes(spot) ? spot : this.headings.find(h => h.closest("section") === spot.closest("section")) ?? null
  }

  mark() {
    const picked = this.headings.indexOf(this.picked)
    const current = picked < 0 ? this.reading() : picked
    this.links.forEach((link, i) => link.classList.toggle("current", i === current))
  }

  // A heading is being read from the scroll that brings it up to a line near
  // the top of the window. A step's last headings may sit too low to reach
  // that line before the page ends. They share the scroll left after the
  // last heading that reaches it, so the last of them is read at the bottom.
  reading() {
    const end = document.documentElement.scrollHeight - innerHeight
    const from = this.headings.map(heading => heading.getBoundingClientRect().top + scrollY - TOP)
    const low = from.findIndex(at => at > end)
    if (low >= 0) {
      const start = low > 0 ? Math.max(0, from[low - 1]) : 0
      const share = (end - start) / (from.length - low)
      for (let i = low; i < from.length; i++) from[i] = start + share * (i - low + 1)
    }
    let current = 0
    from.forEach((at, i) => { if (scrollY + 2 >= at) current = i })
    return current
  }
}

// The line near the top of the window, in pixels.
const TOP = 120

function slug(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "section"
}
