import { Controller } from "@hotwired/stimulus"

// The new site's guide in steps, as guide_video_controller.js does for the
// one long guide, but with no button. A recording plays while a quarter of
// it shows, and pauses when it is scrolled away. A click on it, or Enter or
// Space while it has the focus, pauses it, or plays it again, for good. With
// reduced motion it waits on its poster until a click plays it.
export default class extends Controller {
  static targets = ["video"]

  connect() {
    this.wanted = !matchMedia("(prefers-reduced-motion: reduce)").matches
    this.showing = false
    this.observer = new IntersectionObserver(([entry]) => {
      this.showing = entry.isIntersecting
      this.update()
    }, { threshold: 0.25 })
    this.observer.observe(this.videoTarget)
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
    this.videoTarget.pause()
  }

  toggle(event) {
    event.preventDefault()
    this.wanted = !this.wanted
    this.update()
  }

  update() {
    if (this.wanted && this.showing) this.videoTarget.play().catch(() => {})
    else this.videoTarget.pause()
    this.videoTarget.title = this.wanted ? "click to pause" : "click to play"
    this.videoTarget.setAttribute("aria-pressed", String(!this.wanted))
    this.element.classList.toggle("paused", !this.wanted)
  }
}
