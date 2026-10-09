import { Controller } from "@hotwired/stimulus"
import { confetti } from "confetti"

// The rock that asks a participant how playground is going, on the new site
// (nps_responses/_rock.html.erb). The server puts it on the page only when
// nps.exe would open by itself on the old desktop (NpsResponse.ask?).
//
// It sits still in the corner, with a line in its bubble, a different one
// each time it shows. It shakes more the closer the pointer gets: still
// outside a radius round its middle, a little at its edge, fully on the
// rock. A click opens the form in a popup. A press that moves more than 6px
// drags it instead: it trembles and pleads, with a new line every 1.1
// seconds, more desperate near the bin that rises in the bottom left. Let go
// over the bin, it falls in, the bin fills and says one last line, and the
// rock stays away for 12 hours in this browser. Let go anywhere else, it
// springs back. Delete or Backspace on the rock, or "not now", which shows
// on keyboard focus, put it in the bin too.
//
// On a phone the rock, the bin, and "not now" hide (new_site.css), and a 0
// to 10 strip stands in their place. A number opens the popup with that
// score picked.
//
// A sent answer closes the popup, confetti falls over the whole screen, and
// the rock, or the strip, says thanks, then goes. The answer, like the bin,
// keeps it away for 12 hours in this browser, under the same key nps.exe
// uses on the old desktop. Where storage is blocked it shows on each load
// until the server stops asking. Less motion asked for: no shake, tremble,
// fall, or confetti.
const LINES = [
  ["psst! how's playground going?", "tell me"],
  ["hey you. yeah, you.", "how's it going?"],
  ["i'm just a rock, but i care.", "how's playground?"],
  ["knock knock. it's the rock.", "got a sec?"],
  ["having fun? not having fun?", "tell the rock"],
  ["the rock would like your opinion.", "give it"],
  ["how's your pet coming along?", "tell me"]
]
const PLEAD = ["wait wait wait", "put me down 😭", "i have so much to live for", "i'll be good, i promise", "not the bin!!", "noooo", "i was gonna ask nicely!!", "this is rock abuse"]
const DESPERATE = ["i can see the bin!!", "please please please", "tell my pet i loved them", "not like this", "i'm too young to be trash"]
const THANKS = ["you rock!", "thanks!! you rock", "yay, thank you!"]

const INTERVAL = 12 * 60 * 60 * 1000
const LINE_STORE = "playground-rock-line"
const RADIUS = 260
const DRAG_PAST = 6
const NEAR_BIN = 330
const PLEAD_EVERY = 1100
const THANKS_FOR = 2300

const pick = (pool, not) => {
  const choices = pool.filter(line => line !== not)
  return choices[Math.floor(Math.random() * choices.length)]
}

export default class extends Controller {
  static targets = ["rock", "say", "picture", "skip", "bin", "strip", "scale", "stripThanks", "dialog", "form", "error", "live"]
  static values = { store: String }

  connect() {
    this.reduced = matchMedia("(prefers-reduced-motion: reduce)")
    this.noHover = matchMedia("(hover: none)")
    this.timers = []
    this.shake = 0
    this.element.hidden = window.top !== window || this.skipped()
    if (!this.element.hidden) this.newLine()
  }

  disconnect() {
    this.reset()
  }

  // Turbo keeps a copy of the page it leaves, for Back: the copy shows the
  // rock at rest, or none once it went.
  leave() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    const gone = this.dismissing || this.thanking
    this.reset()
    if (gone) this.element.hidden = true
  }

  reset() {
    this.timers.forEach(clearTimeout)
    this.timers = []
    clearInterval(this.pleading)
    cancelAnimationFrame(this.frame)
    this.frame = 0
    this.grab = null
    this.unfollow()
    this.dismissing = this.thanking = false
    this.rockTarget.classList.remove("is-dragging", "is-falling", "is-thanking", "is-gone", "bubble-right")
    for (const el of [this.rockTarget, this.pictureTarget]) el.removeAttribute("style")
    this.binTarget.classList.remove("is-shown", "is-hot", "is-full", "is-saying")
  }

  later(fn, ms) {
    this.timers.push(setTimeout(fn, ms))
  }

  // When the rock was last put in the bin, or answered, in this browser.
  skipped() {
    try {
      const since = Date.now() - Number(localStorage.getItem(this.storeValue))
      return since >= 0 && since < INTERVAL
    } catch {
      return false
    }
  }

  note() {
    try {
      localStorage.setItem(this.storeValue, String(Date.now()))
    } catch {
      // Nothing remembers it.
    }
  }

  // A line for the bubble, never the one it said last time.
  newLine() {
    let last = null
    try {
      last = localStorage.getItem(LINE_STORE)
    } catch {
      // Any line will do.
    }
    const choices = LINES.map((_, i) => i).filter(i => String(i) !== last)
    const i = choices[Math.floor(Math.random() * choices.length)]
    try {
      localStorage.setItem(LINE_STORE, String(i))
    } catch {
      // The next one may repeat it.
    }
    this.sayLine(LINES[i])
  }

  sayLine([say, link]) {
    const end = document.createElement("u")
    end.textContent = link
    this.sayTarget.replaceChildren(`${say} `, end)
  }

  get busy() {
    return this.dismissing || this.thanking
  }

  // The shake. The pointer's place is kept, and one frame loop eases the
  // shake toward how close it is and turns it into a tilt and a jitter. The
  // loop stops once the rock is still.
  near(event) {
    if (event.pointerType === "touch") return
    this.pointer = [event.clientX, event.clientY]
    this.wake()
  }

  far() {
    this.pointer = null
    this.wake()
  }

  wake() {
    if (!this.frame && !this.element.hidden) this.frame = requestAnimationFrame(now => this.tick(now))
  }

  closeness() {
    const rock = this.rockTarget
    if (this.reduced.matches || this.busy || this.grab?.moving || this.dialogTarget.open || !rock.getClientRects().length) return 0
    if (rock.matches(":focus-visible")) return 1
    if (!this.pointer || this.noHover.matches) return 0
    const [x, y] = this.pointer
    const box = this.pictureTarget.getBoundingClientRect()
    const bubble = rock.querySelector(".nps-bubble").getBoundingClientRect()
    if (x >= box.left && x <= box.right && y >= box.top && y <= box.bottom) return 1
    // The bubble opens the form too.
    const onBubble = x >= bubble.left && x <= bubble.right && y >= bubble.top && y <= bubble.bottom
    const away = Math.hypot(x - (box.left + box.width / 2), y - (box.top + box.height / 2))
    const close = Math.min(1, Math.max(0, (RADIUS - away) / (RADIUS - box.width / 2)))
    return Math.max(close * close, onBubble ? 0.7 : 0)
  }

  tick(now) {
    this.frame = 0
    const step = Math.min(64, this.last ? now - this.last : 16)
    this.last = now
    const target = this.closeness()
    this.shake += (target - this.shake) * (1 - Math.exp(-step / (target > this.shake ? 140 : 280)))
    if (target === 0 && this.shake < 0.004) {
      this.shake = 0
      this.last = 0
      if (!this.grab?.moving && !this.busy) this.pictureTarget.style.transform = ""
      return
    }
    this.phase = (this.phase ?? 0) + (step / 1000) * 2 * Math.PI * (2 + 5 * this.shake)
    this.jitter = (this.jitter ?? 0) + (step / 1000) * 2 * Math.PI * 13
    const s = this.shake
    const tilt = s * 9 * (0.8 * Math.sin(this.phase) + 0.2 * Math.sin(this.phase * 2.3 + 1))
    const x = s * 2.6 * (0.6 * Math.sin(this.jitter) + 0.4 * Math.sin(this.jitter * 1.9 + 2))
    const y = s * 1.4 * Math.sin(this.jitter * 1.4 + 0.5)
    this.pictureTarget.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px) rotate(${tilt.toFixed(2)}deg)`
    this.frame = requestAnimationFrame(now => this.tick(now))
  }

  // The drag. The press is caught at once, but turns into a drag only past
  // 6px, so a plain click still opens the form. The pointer is followed on
  // the whole window until it lets go, wherever it goes.
  press(event) {
    if (event.button !== 0 || !event.isPrimary || this.busy) return
    this.grab = { id: event.pointerId, x0: event.clientX, y0: event.clientY, dx: 0, dy: 0, moving: false }
    this.follow ??= { pointermove: e => this.drag(e), pointerup: e => this.release(e), pointercancel: e => this.release(e) }
    for (const [type, fn] of Object.entries(this.follow)) addEventListener(type, fn)
  }

  unfollow() {
    for (const [type, fn] of Object.entries(this.follow ?? {})) removeEventListener(type, fn)
  }

  drag(event) {
    const grab = this.grab
    if (!grab || event.pointerId !== grab.id) return
    grab.dx = event.clientX - grab.x0
    grab.dy = event.clientY - grab.y0
    if (!grab.moving && Math.hypot(grab.dx, grab.dy) > DRAG_PAST) this.startDrag()
  }

  release(event) {
    const grab = this.grab
    if (!grab || event.pointerId !== grab.id) return
    this.grab = null
    this.unfollow()
    if (!grab.moving) return
    // The click that follows a drag opens nothing.
    this.dragged = true
    setTimeout(() => { this.dragged = false }, 0)
    clearInterval(this.pleading)
    if (event.type === "pointerup" && this.overBin(this.center(grab))) this.dropInBin(grab.dx, grab.dy)
    else this.springBack()
  }

  startDrag() {
    const grab = this.grab
    grab.moving = true
    grab.near = false
    grab.vx = 0
    grab.lastDx = 0
    const box = this.pictureTarget.getBoundingClientRect()
    grab.home = [box.left + box.width / 2, box.top + box.height / 2]
    this.calm = [...this.sayTarget.childNodes].map(node => node.cloneNode(true))
    this.rockTarget.classList.add("is-dragging")
    this.showBin()
    this.plead()
    this.pleading = setInterval(() => this.plead(), PLEAD_EVERY)
    requestAnimationFrame(now => this.dragFrame(now))
  }

  center(grab) {
    return [grab.home[0] + grab.dx, grab.home[1] + grab.dy]
  }

  // The bin's basket, drawn in the middle of its picture, and a little
  // above it.
  binBox() {
    const box = this.binTarget.querySelector(".nps-bin-empty").getBoundingClientRect()
    return { left: box.left + box.width * 0.15, right: box.right - box.width * 0.15, top: box.top + box.height * 0.15, bottom: box.bottom, middle: [box.left + box.width / 2, box.top + box.height / 2] }
  }

  overBin([x, y]) {
    const bin = this.binBox()
    return x > bin.left - 16 && x < bin.right + 16 && y > bin.top - 50 && y < bin.bottom
  }

  plead() {
    this.sayTarget.textContent = pick(this.grab?.near ? DESPERATE : PLEAD, this.sayTarget.textContent)
  }

  dragFrame(now) {
    const grab = this.grab
    if (!grab?.moving) return
    const step = grab.last ? Math.max(8, now - grab.last) : 16
    grab.last = now
    grab.vx += ((grab.dx - grab.lastDx) / step * 16 - grab.vx) * 0.2
    grab.lastDx = grab.dx
    this.rockTarget.style.transform = `translate(${grab.dx}px, ${grab.dy}px)`
    const [x, y] = this.center(grab)
    const bin = this.binBox()
    const near = Math.hypot(x - bin.middle[0], y - bin.middle[1]) < NEAR_BIN
    const over = this.overBin([x, y])
    this.binTarget.classList.toggle("is-hot", over)
    if (near !== grab.near) {
      grab.near = near
      this.plead()
    }
    // In the left half of the screen the bubble moves to the rock's right,
    // so it stays on the screen.
    this.rockTarget.classList.toggle("bubble-right", x < innerWidth / 2)
    // It leans toward where it goes, and trembles, worse near the bin.
    if (!this.reduced.matches) {
      const fear = over ? 2.2 : near ? 1.6 : 1
      const tilt = Math.max(-18, Math.min(18, grab.vx * 1.4))
      const tremble = fear * (1.2 * Math.sin(now / 21) + (Math.random() - 0.5))
      const jx = fear * (Math.random() - 0.5) * 1.6
      this.pictureTarget.style.transform = `translate(${jx.toFixed(2)}px, 0) rotate(${(tilt + tremble).toFixed(2)}deg)`
    }
    requestAnimationFrame(now => this.dragFrame(now))
  }

  springBack() {
    const rock = this.rockTarget
    rock.classList.remove("is-dragging", "bubble-right")
    this.sayTarget.replaceChildren(...this.calm)
    this.pictureTarget.style.transform = ""
    rock.style.transition = this.reduced.matches ? "none" : "transform 0.55s cubic-bezier(0.34, 1.56, 0.64, 1)"
    rock.style.transform = ""
    this.hideBin()
    this.later(() => { rock.style.transition = "" }, 600)
  }

  showBin() {
    this.binTarget.classList.remove("is-full", "is-saying", "is-hot")
    this.binTarget.classList.add("is-shown")
  }

  hideBin() {
    this.binTarget.classList.remove("is-shown", "is-hot")
  }

  key(event) {
    if (event.key !== "Delete" && event.key !== "Backspace") return
    event.preventDefault()
    this.skip()
  }

  // From the keyboard, or "not now": the rock cries out and flies to the bin.
  skip() {
    if (this.busy || !this.rockTarget.getClientRects().length) return
    this.dismissing = true
    this.rockTarget.classList.add("is-dragging")
    this.sayTarget.textContent = "noooo"
    this.showBin()
    if (this.reduced.matches) return this.dropInBin(0, 0)
    this.later(() => {
      const box = this.pictureTarget.getBoundingClientRect()
      const bin = this.binBox()
      const dx = bin.middle[0] - (box.left + box.width / 2)
      const dy = bin.top - 30 - (box.top + box.height / 2)
      this.rockTarget.classList.add("bubble-right")
      this.rockTarget.style.transition = "transform 0.7s cubic-bezier(0.45, 0, 0.3, 1)"
      this.rockTarget.style.transform = `translate(${dx}px, ${dy}px)`
      this.later(() => this.dropInBin(dx, dy), 720)
    }, 300)
  }

  // Over the bin's mouth, down behind its front, and the bin fills and says
  // its line. The rock is gone for 12 hours.
  dropInBin(dx, dy) {
    this.dismissing = true
    this.note()
    const rock = this.rockTarget
    const hadFocus = this.element.contains(document.activeElement)
    this.binTarget.classList.add("is-hot")
    const fill = () => {
      this.binTarget.classList.remove("is-hot")
      this.binTarget.classList.add("is-full", "is-saying")
      this.liveTarget.textContent = "the rock is in the bin for 12 hours."
      this.later(() => { this.binTarget.classList.remove("is-saying"); this.hideBin() }, 1400)
      this.later(() => {
        if (hadFocus || this.element.contains(document.activeElement)) this.focusPage()
        this.element.hidden = true
      }, 1750)
    }
    if (this.reduced.matches) {
      rock.style.visibility = "hidden"
      return fill()
    }
    const box = this.pictureTarget.getBoundingClientRect()
    const bin = this.binBox()
    const ax = dx + bin.middle[0] - (box.left + box.width / 2)
    const ay = dy + bin.top - 30 - (box.top + box.height / 2)
    this.pictureTarget.style.transform = ""
    rock.style.transition = "transform 0.18s ease-out"
    rock.style.transform = `translate(${ax}px, ${ay}px)`
    this.later(() => {
      rock.classList.add("is-falling")
      rock.style.transition = "transform 0.35s cubic-bezier(0.55, 0, 0.9, 0.45)"
      rock.style.transform = `translate(${ax}px, ${ay + 170}px) scale(0.85)`
    }, 200)
    this.later(fill, 560)
  }

  // Focus never stays on what hides: it goes to the button on to the
  // guide's next step, or to the page's heading.
  focusPage() {
    const to = document.querySelector(".guide-pager .guide-next") ?? document.querySelector("main h1, main h2") ?? document.querySelector("main")
    if (!to) return
    if (!to.matches("a[href], button") && !to.hasAttribute("tabindex")) to.setAttribute("tabindex", "-1")
    to.focus({ preventScroll: true })
  }

  // The popup.
  open(event) {
    if (this.dragged) {
      event.preventDefault()
      this.dragged = false
      return
    }
    if (this.busy) return
    this.show()
  }

  rate(event) {
    this.show(event.currentTarget.value)
  }

  show(score) {
    if (this.dialogTarget.open) return
    this.errorTarget.hidden = true
    this.dialogTarget.showModal()
    this.wake()
    const box = this.formTarget.querySelector(`input[type=radio][value="${score}"]`)
    if (box) {
      box.checked = true
      box.dispatchEvent(new Event("change", { bubbles: true }))
      this.formTarget.querySelector("textarea")?.focus()
    } else {
      (this.formTarget.querySelector("input[type=radio]:checked") ?? this.formTarget.querySelector("input[type=radio]"))?.focus()
    }
  }

  close() {
    this.dialogTarget.close()
  }

  closed() {
    this.wake()
  }

  async send(event) {
    event.preventDefault()
    if (this.sending) return
    this.sending = true
    const submit = this.formTarget.querySelector("button[type=submit]")
    submit.disabled = true
    let status = 0
    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        body: new FormData(this.formTarget),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" },
        credentials: "same-origin"
      })
      status = response.status
    } catch {
      // Sent nothing.
    }
    this.sending = false
    if (status === 201) return this.thank()
    submit.disabled = false
    this.errorTarget.textContent = status === 422 ? "pick a number and fill in the * ones first." : "that didn't send. try again in a moment."
    this.errorTarget.hidden = false
  }

  // No thanks screen: the popup closes, confetti falls, and the rock, or on
  // a phone the strip, says thanks, then goes.
  thank() {
    this.note()
    this.thanking = true
    this.dialogTarget.close()
    this.formTarget.reset()
    confetti()
    const line = pick(THANKS)
    this.liveTarget.textContent = "feedback sent. thanks!"
    if (this.rockTarget.getClientRects().length) {
      this.rockTarget.classList.add("is-thanking")
      this.rockTarget.setAttribute("aria-label", "thanks for the feedback")
      this.sayTarget.textContent = line
      this.pictureTarget.style.transform = ""
    } else {
      this.scaleTarget.hidden = true
      this.stripThanksTarget.textContent = line
      this.stripThanksTarget.hidden = false
      this.stripThanksTarget.focus({ preventScroll: true })
    }
    this.later(() => {
      if (this.element.contains(document.activeElement)) this.focusPage()
      this.rockTarget.classList.add("is-gone")
      this.stripTarget.classList.add("is-gone")
      this.later(() => { this.element.hidden = true }, this.reduced.matches ? 0 : 650)
    }, THANKS_FOR)
  }
}
