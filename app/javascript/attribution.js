// Where this browser came from, worked out here and kept here alone, in
// localStorage, with no cookie and no id (TrafficSource). Each touch is a
// source, a medium and a campaign:
//
// - A link tagged ?utm_source= (or ?ref=) names its own, with utm_medium
//   and utm_campaign. Each is trimmed, lowercased, spaces as dashes, and cut
//   to 40 characters.
// - Otherwise the referring site names it, by its host alone: Slack, search
//   engines, X, GitHub, Discord, YouTube, email and the Hack Club site have
//   names, and any other site is its host. No referrer, or this site, is
//   "direct".
// - A first visit that starts on Stardance's or the clubs' guide, with no
//   tag, comes from that guide, with the referring site as its medium.
//
// First touch is set once and never changes. Last touch is the latest
// arrival that was not direct, so typing the address or a bookmark keeps
// what brought the reader before. A browser that used the site before this
// counting began has an unknown first touch. Pages on this site, and the
// windows of the desktop, are not arrivals.
//
// The guides send the touches with the anonymous counts of how far readers
// get (guide_progress_controller.js), and the login carries them to count
// where new accounts come from. Nothing else reads them.
const KEY = "playground-traffic-source"
const MAX = 40
const DIRECT = Object.freeze({ source: "direct", medium: "", campaign: "" })
const UNKNOWN = Object.freeze({ source: "unknown", medium: "", campaign: "" })
const ENTRY_GUIDES = ["stardance", "clubs"]

// Referring hosts that have a name, in order: a mail host before the
// search engine on the same domain.
const HOSTS = [
  [/^mail\.google\.com$|^outlook\.(live|office)\.com$|^mail\.yahoo\.com$|^com\.google\.android\.gm$/, "email"],
  [/(^|\.)slack\.com$|^slack-redir\.net$|^com\.slack$/, "slack"],
  [/^(www\.)?google\.[a-z.]+$|(^|\.)bing\.com$|(^|\.)duckduckgo\.com$|^search\.yahoo\.com$|^(www\.)?yandex\.[a-z.]+$|(^|\.)baidu\.com$|(^|\.)ecosia\.org$|^search\.brave\.com$|(^|\.)kagi\.com$|(^|\.)startpage\.com$|^com\.google\.android\.googlequicksearchbox$/, "search"],
  [/^t\.co$|(^|\.)x\.com$|(^|\.)twitter\.com$|^com\.twitter\.android$/, "x"],
  [/(^|\.)github\.com$/, "github"],
  [/(^|\.)discord(app)?\.com$|^discord\.gg$|^com\.discord$/, "discord"],
  [/(^|\.)youtube\.com$|^youtu\.be$|^com\.google\.android\.youtube$/, "youtube"],
  [/^(www\.)?hackclub\.com$/, "hack club site"]
]
const MEDIUM = { search: "organic", email: "email" }

// Every source this script can name for itself. The server knows them too.
export const CHANNELS = ["direct", "unknown", ...new Set(HOSTS.map(([, name]) => name)), ...ENTRY_GUIDES]

export function clean(value) {
  return typeof value === "string" ? value.trim().toLowerCase().replace(/\s+/g, "-").slice(0, MAX) : ""
}

// A referrer's host, without www., or "" for none or one that is not a URL.
export function referrerHost(referrer) {
  try {
    return new URL(referrer).hostname.toLowerCase().replace(/^www\./, "")
  } catch {
    return ""
  }
}

// The touch an arrival at href from referrer makes, on a site at host.
// first: whether this browser has no first touch yet.
export function parseTouch({ href, referrer = "", host, first = false }) {
  const url = new URL(href)
  const query = url.searchParams
  const tagged = clean(query.get("utm_source") || query.get("ref") || "")
  if (tagged) return { source: tagged, medium: clean(query.get("utm_medium") || ""), campaign: clean(query.get("utm_campaign") || "") }
  const from = referrerHost(referrer)
  const self = host.toLowerCase().replace(/^www\./, "")
  const site = !from || from === self ? DIRECT : siteTouch(from)
  const guide = ENTRY_GUIDES.find(slug => url.pathname === `/${slug}` || url.pathname.startsWith(`/${slug}/`))
  if (first && guide) return { source: guide, medium: site.source, campaign: "" }
  return site
}

function siteTouch(host) {
  const name = HOSTS.find(([pattern]) => pattern.test(host))?.[1]
  if (name) return { source: name, medium: MEDIUM[name] || "referral", campaign: "" }
  return { source: clean(host), medium: "referral", campaign: "" }
}

// The touches after an arrival: the first one stays, the last one moves on
// to any arrival that is not direct. before: the browser used the site
// before counting began, so its first touch is unknown.
export function applyTouch(saved, touch, { before = false } = {}) {
  const first = valid(saved?.first) || (before ? UNKNOWN : touch)
  const last = touch.source !== "direct" ? touch : valid(saved?.last) || first
  return { first, last }
}

function valid(touch) {
  return touch && typeof touch.source === "string" && touch.source ? { source: touch.source, medium: String(touch.medium || ""), campaign: String(touch.campaign || "") } : null
}

let memory = null

function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY))
  } catch {
    return memory
  }
}

function save(record) {
  memory = record
  try {
    localStorage.setItem(KEY, JSON.stringify(record))
  } catch {
    // Private browsing, or storage turned off: memory keeps it for this page.
  }
}

// Whether this browser kept anything of the site's before counting began.
function usedBefore() {
  try {
    return Object.keys(localStorage).some(key => key.startsWith("playground-") && key !== KEY)
  } catch {
    return false
  }
}

// Counts this page as an arrival, once. A page inside the desktop's
// windows, or reached from another page of the site, is direct, so it only
// sets a first touch that is missing. The admin pages are no arrival.
export function capture(where = location, referrer = document.referrer) {
  if (where.pathname.startsWith("/admin")) return touches()
  const saved = load()
  const touch = parseTouch({ href: where.href, referrer, host: where.hostname, first: !valid(saved?.first) })
  const next = applyTouch(saved, touch, { before: !valid(saved?.first) && usedBefore() })
  save(next)
  return next
}

// This browser's touches now, as { first, last }.
export function touches() {
  const saved = load()
  const first = valid(saved?.first) || DIRECT
  return { first, last: valid(saved?.last) || first }
}

// The touches as the parameters the server reads: first_source and so on.
export function touchParams({ first, last } = touches()) {
  const params = {}
  for (const [prefix, touch] of [["first", first], ["last", last]]) {
    for (const field of ["source", "medium", "campaign"]) params[`${prefix}_${field}`] = touch[field]
  }
  return params
}

// The login to Hack Club carries the touches on its address, which OmniAuth
// keeps in the session for the round trip alone, so a new account counts
// where it came from (SessionsController). Nothing else goes with it.
function carryToLogin(event) {
  const form = event.target
  if (!(form instanceof HTMLFormElement)) return
  const action = new URL(form.action, location.href)
  if (action.origin !== location.origin || action.pathname !== "/auth/hack_club") return
  for (const [name, value] of Object.entries(touchParams())) action.searchParams.set(name, value)
  form.action = action.href
}

if (!window.playgroundAttribution) {
  window.playgroundAttribution = true
  capture()
  document.addEventListener("submit", carryToLogin, true)
}
