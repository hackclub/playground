// Confetti over the whole screen: paper bits in the site's colours fall
// from across the top, sway, turn over, and fade, in about 2.3 seconds. More
// screen takes more bits, up to a cap. They draw on a canvas laid over the
// page, in the top layer where a browser has one, so they show over an open
// dialog too. It takes no clicks, and it is removed once the bits are gone.
// It hangs on the root element, so it stays while Turbo swaps the page's
// body under it. Nothing shows for someone who asks for less motion.
const COLORS = ["#3a70b8", "#9bb8e0", "#2b3a4d", "#3f9a4b", "#d99a1e", "#c8423b", "#ffffff"]
const DURATION = 2300
const FADE = 500

export function confetti(doc = document) {
  const view = doc.defaultView
  if (!view || view.matchMedia("(prefers-reduced-motion: reduce)").matches) return null
  const width = view.innerWidth, height = view.innerHeight, scale = Math.min(view.devicePixelRatio || 1, 2)
  const canvas = doc.createElement("canvas")
  canvas.className = "confetti"
  canvas.setAttribute("aria-hidden", "true")
  Object.assign(canvas.style, {
    position: "fixed", inset: "0", width: "100vw", height: "100vh", margin: "0", padding: "0", border: "0",
    background: "transparent", pointerEvents: "none", zIndex: "2147483647"
  })
  canvas.width = Math.round(width * scale)
  canvas.height = Math.round(height * scale)
  const popover = "showPopover" in canvas
  if (popover) canvas.popover = "manual"
  doc.documentElement.append(canvas)
  if (popover) canvas.showPopover()
  const ink = canvas.getContext("2d")
  ink.scale(scale, scale)

  // About one bit for each 7,000 square pixels: 185 on a 1440x900 screen,
  // and never fewer than 60 or more than 260.
  const count = Math.round(Math.min(260, Math.max(60, width * height / 7000)))
  const bits = Array.from({ length: count }, (_, i) => ({
    x: Math.random() * width,
    // Some start above the screen, so the bits rain in over the first second.
    y: -10 - Math.random() * height * 0.6,
    vx: (Math.random() - 0.5) * 2,
    vy: 2 + Math.random() * 4,
    w: 6 + Math.random() * 6, h: 3 + Math.random() * 4,
    spin: Math.random() * Math.PI, turn: (Math.random() - 0.5) * 0.3,
    sway: Math.random() * Math.PI * 2, swaySpeed: 0.04 + Math.random() * 0.06,
    color: COLORS[i % COLORS.length]
  }))

  const start = view.performance.now()
  let last = start
  const done = () => {
    if (!canvas.isConnected) return
    if (popover) canvas.hidePopover()
    canvas.remove()
  }
  const draw = now => {
    if (!canvas.isConnected) return
    const age = now - start
    if (age >= DURATION) return done()
    const step = Math.min(3, (now - last) / 16.7)
    last = now
    ink.clearRect(0, 0, width, height)
    ink.globalAlpha = Math.min(1, (DURATION - age) / FADE)
    for (const bit of bits) {
      bit.vy = Math.min(9, bit.vy + 0.16 * step)
      bit.sway += bit.swaySpeed * step
      bit.x += (bit.vx + Math.sin(bit.sway) * 1.2) * step
      bit.y += bit.vy * step
      bit.spin += bit.turn * step
      ink.save()
      ink.translate(bit.x, bit.y)
      ink.rotate(bit.spin)
      // A bit turning over shows its edge, so it narrows and widens.
      ink.scale(1, Math.cos(bit.sway * 1.5))
      ink.fillStyle = bit.color
      ink.fillRect(-bit.w / 2, -bit.h / 2, bit.w, bit.h)
      if (bit.color === "#ffffff") {
        ink.strokeStyle = "rgba(43, 58, 77, 0.5)"
        ink.lineWidth = 1
        ink.strokeRect(-bit.w / 2, -bit.h / 2, bit.w, bit.h)
      }
      ink.restore()
    }
    view.requestAnimationFrame(draw)
  }
  view.requestAnimationFrame(draw)
  // A hidden page draws no frames, so the canvas goes on time regardless.
  view.setTimeout(done, DURATION + 300)
  return canvas
}
