import { Controller } from "@hotwired/stimulus"

// A recording in the guide plays while a quarter of it shows, and pauses
// when it is scrolled away. Its button pauses it, or plays it again, for
// good. With reduced motion it waits on its poster until the button plays it.
export default class extends Controller {
  static targets = ["video", "toggle"]

  connect() {
    this.wanted = !matchMedia("(prefers-reduced-motion: reduce)").matches
    this.showing = false
    this.observer = new IntersectionObserver(([entry]) => {
      this.showing = entry.isIntersecting
      this.update()
    }, { threshold: 0.25 })
    this.observer.observe(this.videoTarget)
    this.toggleTarget.hidden = false
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
    this.videoTarget.pause()
  }

  toggle() {
    this.wanted = !this.wanted
    this.update()
  }

  update() {
    if (this.wanted && this.showing) this.videoTarget.play().catch(() => {})
    else this.videoTarget.pause()
    this.toggleTarget.textContent = this.wanted ? "pause" : "play"
    this.toggleTarget.setAttribute("aria-label", `${this.wanted ? "pause" : "play"} the recording`)
    this.element.classList.toggle("paused", !this.wanted)
  }
}
