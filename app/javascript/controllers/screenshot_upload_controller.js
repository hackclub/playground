import { Controller } from "@hotwired/stimulus"

// The client half of the screenshot uploads. It exists
// for speed and clear messages; the server repeats every check. Order:
// format -> too large? -> downscale -> too small? -> size -> send.
// Every image is redrawn on a canvas and re-encoded, which also drops EXIF
// data such as GPS location before the file leaves the device.
//
// A pet holds up to perPet screenshots in order, and the first is its cover.
// They sit in a grid of perPet cells: the screenshots, a cell that adds more,
// and empty cells. Files dropped anywhere on the grid, or chosen from the add
// cell, upload one after another, each in its own cell with its own progress.
// A screenshot moves by drag or by the arrow keys, and the order saves after
// each move. A click, Enter, or a file dropped on one replaces it, and its ×
// or Delete removes it. Only the list changes, so nothing typed in the edit
// form is lost. Each change tells ship.exe, which checks the pet again.
export default class extends Controller {
  static targets = ["grid", "list", "add", "empty", "template", "input", "status"]
  static values = { url: String, orderUrl: String, maxEdge: Number, minWidth: Number, minHeight: Number, maxBytes: Number, types: String, quality: Number, perPet: Number }

  connect() {
    this.queue = Promise.resolve()
    this.errors = []
    this.depth = 0
    this.relabel()
  }

  get thumbs() { return [...this.listTarget.children] }
  get settled() { return this.thumbs.filter((thumb) => !thumb.classList.contains("pending")) }
  get full() { return this.thumbs.length >= this.perPetValue }

  // Adding, from the add cell's file picker or a drop on the grid.
  pick() {
    if (this.full) return
    this.replacing = null
    this.inputTarget.click()
  }

  chosen() {
    const files = [...this.inputTarget.files]
    this.inputTarget.value = ""
    const thumb = this.replacing
    this.replacing = null
    this.take(files, thumb)
  }

  // Files dragged over the grid tint it. The browser tells each cell the
  // drag comes and goes, so a count of those keeps the tint on across them.
  // A drag that holds no files, such as a picture from the page, changes
  // nothing.
  enter(event) {
    if (!carriesFiles(event)) return
    this.depth++
    this.gridTarget.classList.add("dropping")
  }

  over(event) {
    if (carriesFiles(event)) event.preventDefault()
  }

  leave(event) {
    if (!carriesFiles(event) || --this.depth > 0) return
    this.depth = 0
    this.gridTarget.classList.remove("dropping")
  }

  drop(event) {
    if (!carriesFiles(event)) return
    event.preventDefault()
    this.depth = 0
    this.gridTarget.classList.remove("dropping")
    this.take([...event.dataTransfer.files])
  }

  // Replacing one, by a click on it or a file dropped on it.
  pickFor(event) {
    const thumb = event.currentTarget
    if (this.dragged || event.target.closest(".remove") || thumb.classList.contains("pending")) return
    this.replacing = thumb
    this.inputTarget.click()
  }

  overThumb(event) {
    if (!carriesFiles(event) || event.currentTarget.classList.contains("pending")) return
    event.preventDefault()
    event.currentTarget.classList.add("hover")
  }

  leaveThumb(event) { event.currentTarget.classList.remove("hover") }

  dropOn(event) {
    const thumb = event.currentTarget
    thumb.classList.remove("hover")
    if (thumb.classList.contains("pending") || !carriesFiles(event)) return
    event.preventDefault()
    event.stopPropagation()
    this.depth = 0
    this.gridTarget.classList.remove("dropping")
    this.take([...event.dataTransfer.files], thumb)
  }

  // The first file replaces the screenshot given, if any, and the rest go
  // on the end. A file past the room there is now waits its turn, when one
  // ahead of it may have failed and left room.
  take(files, replacing = null) {
    if (!files.length) return
    this.errors = []
    this.say("")
    if (replacing) this.enqueue(files.shift(), replacing, replacing.dataset.id)
    for (const file of files) {
      if (!this.full) {
        this.enqueue(file, this.newThumb(), null)
        continue
      }
      this.queue = this.queue.then(() => {
        if (this.full) return this.fail(file, `a pet holds up to ${this.perPetValue} screenshots. remove one to add another.`)
        const thumb = this.newThumb()
        thumb.classList.add("busy")
        return this.upload(file, thumb, null)
      })
    }
    this.relabel()
  }

  newThumb() {
    const thumb = this.templateTarget.content.firstElementChild.cloneNode(true)
    thumb.classList.add("pending")
    this.listTarget.append(thumb)
    this.state(thumb, "waiting…")
    return thumb
  }

  enqueue(file, thumb, replace) {
    thumb.classList.add("busy")
    this.queue = this.queue.then(() => this.upload(file, thumb, replace))
  }

  async upload(file, thumb, replace) {
    const image = thumb.querySelector("img")
    const before = image.getAttribute("src")
    let preview
    try {
      const blob = await this.prepare(file, thumb)
      preview = URL.createObjectURL(blob)
      image.src = preview
      const body = await this.send(blob, thumb, replace)
      // The stored image loads first, so the swap from the preview does not flash.
      const stored = new Image()
      stored.src = body.url
      await stored.decode().catch(() => {})
      image.src = body.url
      thumb.dataset.id = body.id
      this.settle(thumb)
      if (!this.errors.length) this.say("uploaded ✓")
      this.dispatch("changed", { detail: { url: body.url } })
    } catch (error) {
      this.fail(file, error.message)
      // Nothing was saved: a replaced screenshot comes back, a new one goes.
      if (replace) {
        if (before) image.src = before
        this.settle(thumb)
      } else {
        thumb.remove()
      }
    } finally {
      if (preview) URL.revokeObjectURL(preview)
      this.relabel()
    }
  }

  // The checks, in order, and the re-encode.
  async prepare(file, thumb) {
    // 1. format: the declared type, then an actual decode
    if (!this.typesValue.split(",").includes(file.type)) throw new Error("use a PNG, JPEG, or WebP screenshot. no GIFs or videos.")
    this.state(thumb, "checking…")
    let bitmap
    try { bitmap = await createImageBitmap(file) } catch { throw new Error("that file isn't a readable image.") }

    // 2-3. too large: scale the long edge down to the limit
    let { width, height } = bitmap
    const scale = Math.min(1, this.maxEdgeValue / Math.max(width, height))
    width = Math.round(width * scale)
    height = Math.round(height * scale)

    // 4. too small: refuse
    if (Math.max(width, height) < this.minWidthValue || Math.min(width, height) < this.minHeightValue) {
      throw new Error(`this image is ${bitmap.width}×${bitmap.height}. screenshots must be at least ${this.minWidthValue}×${this.minHeightValue}.`)
    }

    // re-encode through a canvas: strips metadata, and shrinks until it fits
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    canvas.getContext("2d").drawImage(bitmap, 0, 0, width, height)
    bitmap.close()
    const blob = await this.encode(canvas)

    // 5. size
    if (blob.size > this.maxBytesValue) throw new Error("this image is still too large after shrinking it. try a simpler screenshot.")
    return blob
  }

  // WebP where the browser can write it, JPEG otherwise; lower the quality
  // step by step if the file is over the byte limit.
  async encode(canvas) {
    const type = await this.canEncodeWebp() ? "image/webp" : "image/jpeg"
    for (let quality = this.qualityValue / 100; quality >= 0.5; quality -= 0.1) {
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, type, quality))
      if (blob && blob.size <= this.maxBytesValue) return blob
      if (quality - 0.1 < 0.5) return blob
    }
  }

  async canEncodeWebp() {
    const c = document.createElement("canvas")
    c.width = c.height = 1
    const blob = await new Promise((resolve) => c.toBlob(resolve, "image/webp"))
    return blob?.type === "image/webp"
  }

  send(blob, thumb, replace) {
    return new Promise((resolve, reject) => {
      const form = new FormData()
      form.append("screenshot", blob, blob.type === "image/webp" ? "screenshot.webp" : "screenshot.jpg")
      if (replace) form.append("replace", replace)
      const xhr = new XMLHttpRequest()
      xhr.open("POST", this.urlValue)
      const token = document.querySelector("meta[name=csrf-token]")?.content
      if (token) xhr.setRequestHeader("X-CSRF-Token", token)
      xhr.setRequestHeader("Accept", "application/json")
      xhr.upload.onprogress = (e) => { if (e.lengthComputable) this.progress(thumb, e.loaded / e.total) }
      xhr.onload = () => {
        let body = {}
        try { body = JSON.parse(xhr.responseText) } catch {}
        if (xhr.status === 201) resolve(body)
        else reject(new Error(body.error || `upload failed (${xhr.status})`))
      }
      xhr.onerror = () => reject(new Error("upload failed: check your connection"))
      this.state(thumb, "uploading…")
      xhr.send(form)
    })
  }

  async remove(event) {
    event.stopPropagation()
    const thumb = event.currentTarget.closest(".thumb")
    if (thumb.classList.contains("busy") || !thumb.dataset.id) return
    thumb.classList.add("busy")
    try {
      const response = await this.request("DELETE", `${this.urlValue}/${encodeURIComponent(thumb.dataset.id)}`)
      if (!response.ok && response.status !== 404) throw new Error(await this.problem(response, "removing it failed"))
      const next = thumb.nextElementSibling || thumb.previousElementSibling
      thumb.remove()
      ;(next || this.addTarget).focus()
      this.say("removed ✓")
      this.dispatch("changed")
    } catch (error) {
      thumb.classList.remove("busy")
      this.say(error.message, true)
    }
    this.relabel()
  }

  // Keys on a focused screenshot. The × button's keys are its own.
  key(event) {
    const thumb = event.currentTarget
    if (event.target !== thumb || thumb.classList.contains("pending")) return
    const step = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[event.key]
    if (step) {
      event.preventDefault()
      this.move(thumb, step)
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.replacing = thumb
      this.inputTarget.click()
    } else if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault()
      thumb.querySelector(".remove").click()
    }
  }

  move(thumb, step) {
    const settled = this.settled
    const to = settled.indexOf(thumb) + step
    if (to < 0 || to >= settled.length) return
    if (step < 0) settled[to].before(thumb)
    else settled[to].after(thumb)
    thumb.focus()
    this.relabel()
    this.say(`moved to ${to + 1} of ${settled.length}`)
    this.saveOrder()
  }

  // A drag by mouse, pen, or finger moves a screenshot among the others. A
  // press that barely moves is a click, which replaces it. The screenshot
  // moves in the page as the pointer passes the others, which would end a
  // pointer capture, so the document follows the pointer instead.
  grab(event) {
    const thumb = event.currentTarget
    if (!event.isPrimary || event.button !== 0 || event.target.closest(".remove") || thumb.classList.contains("pending")) return
    const start = { x: event.clientX, y: event.clientY }
    const order = this.settled.map((t) => t.dataset.id).join()
    this.dragged = false
    const move = (e) => {
      if (e.pointerId !== event.pointerId) return
      if (!this.dragged) {
        if (Math.hypot(e.clientX - start.x, e.clientY - start.y) < 6) return
        this.dragged = true
        thumb.classList.add("dragging")
      }
      const over = document.elementFromPoint(e.clientX, e.clientY)?.closest(".thumb")
      if (!over || over === thumb || over.parentElement !== this.listTarget || over.classList.contains("pending")) return
      const box = over.getBoundingClientRect()
      if (e.clientX < box.left + box.width / 2) over.before(thumb)
      else over.after(thumb)
    }
    const end = (e) => {
      if (e.pointerId !== event.pointerId) return
      document.removeEventListener("pointermove", move)
      document.removeEventListener("pointerup", end)
      document.removeEventListener("pointercancel", end)
      thumb.classList.remove("dragging")
      if (this.dragged) {
        thumb.focus()
        this.relabel()
        if (this.settled.map((t) => t.dataset.id).join() !== order) this.saveOrder()
      }
      // The click that ends a drag replaces nothing.
      setTimeout(() => { this.dragged = false })
    }
    document.addEventListener("pointermove", move)
    document.addEventListener("pointerup", end)
    document.addEventListener("pointercancel", end)
  }

  // The order saves after the uploads ahead of it, with the list as it is
  // then, so a move made during an upload counts it too.
  saveOrder() {
    this.orderChanged = true
    this.queue = this.queue.then(async () => {
      if (!this.orderChanged) return
      this.orderChanged = false
      try {
        const response = await this.request("PATCH", this.orderUrlValue, { ids: this.settled.map((thumb) => thumb.dataset.id) })
        if (!response.ok) throw new Error(await this.problem(response, "saving the order failed"))
        this.dispatch("changed")
      } catch (error) {
        this.say(error.message, true)
      }
    })
  }

  request(method, url, body) {
    const headers = { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" }
    if (body) headers["Content-Type"] = "application/json"
    return fetch(url, { method, headers, body: body && JSON.stringify(body) })
  }

  async problem(response, fallback) {
    const body = await response.json().catch(() => ({}))
    return body.error || `${fallback} (${response.status})`
  }

  // Each screenshot's name says where it stands. The add cell shows while
  // there is room, and empty cells fill the rest of the grid.
  relabel() {
    const thumbs = this.thumbs
    thumbs.forEach((thumb, i) => {
      const name = `screenshot ${i + 1} of ${thumbs.length}`
      thumb.setAttribute("aria-label", i === 0 ? `${name}, the cover` : name)
      thumb.classList.toggle("cover", i === 0)
      thumb.querySelector(".remove").setAttribute("aria-label", `remove screenshot ${i + 1}`)
    })
    const free = this.perPetValue - thumbs.length
    this.addTarget.hidden = free <= 0
    this.emptyTargets.forEach((cell, i) => { cell.hidden = i >= free - 1 })
    this.gridTarget.classList.toggle("full", free <= 0)
  }

  state(thumb, text) {
    const caption = thumb.querySelector(".thumb-state")
    caption.textContent = text
    caption.hidden = !text
  }

  progress(thumb, fraction) {
    const bar = thumb.querySelector("progress")
    bar.hidden = false
    bar.value = fraction
  }

  settle(thumb) {
    thumb.classList.remove("pending", "busy")
    thumb.querySelector("progress").hidden = true
    this.state(thumb, "")
  }

  // A file that could not be saved, named, so a batch says which.
  fail(file, message) {
    this.errors.push(`${file.name}: ${message}`)
    this.say(this.errors.join("\n"), true)
  }

  say(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("alert", error)
  }
}

function carriesFiles(event) {
  return [...(event.dataTransfer?.types ?? [])].includes("Files")
}
