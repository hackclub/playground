# Analytics

The site counts how far readers get in the guides, how long they spend there, and where readers and new accounts come from. It does this the way Plausible does: the server keeps aggregate counts, and nothing that identifies a person or a browser. The admin sees the counts on `/admin/stats`.

## What is collected

Each reader's browser works these out for itself and keeps them in `localStorage`, never in a cookie:

- **Where it came from**: a first touch and a last touch, each a source, a medium and a campaign (see below).
- **Its journey through each guide**: the US Eastern day it started the guide, its touches on that day, its engaged time, and the furthest section it has reached.

The server receives these only as parts of anonymous counts, and stores only the counts:

| Table | One row counts | Columns |
|---|---|---|
| `guide_section_days` | browsers that saw a section on a day | day, guide, section, readers |
| `guide_journey_days` | browsers that started a guide on a day, from these sources, and got at least this far in at least this many minutes | day, guide, stage, minutes, first and last source, medium and campaign, readers |
| `signup_source_days` | new accounts made on a day from these sources | day, first and last source, medium and campaign, signups |
| `guide_reader_days` | Stardance and Clubs browsers that read 20 minutes on a day | day, guide, readers |

A browser reports a journey as it moves on: where the server last heard it was, and where it is now. Each count it newly belongs to goes up by one. No count ever goes down, so no report can take one below zero, and each browser counts once in a guide, however many days it reads on.

## What is never collected

- No IP address, user id, cookie id, session id, or browser id is stored with any count.
- The reports to `/guide_journeys`, `/guide_sections` and `/guide_readers` are not logged, so no log line pairs an address with a report. The rate limit counts by a keyed hash of the address and the day, which changes daily and is never stored.
- A signup's touches never go on the account. The login carries them through Hack Club's sign-in in OmniAuth's own session, and they are dropped once counted. The parameters are filtered from the logs. An account that already exists counts nothing.
- No full URL, path, query string, search term, or referrer path is kept. A referrer is reduced to its host.
- Sources with fewer than 3 readers or signups in the days shown are grouped as "other" on the admin page, so a link made for one person does not single them out.

Hosting access logs are outside this app.

## Sources

A touch is a source, a medium, and a campaign:

1. **A tagged link.** `utm_source`, `utm_medium` and `utm_campaign`, with `ref` accepted for `utm_source`. Each is trimmed, lowercased, has spaces turned to dashes, and is cut to 40 characters.
2. **The referring site**, when the link has no tag. Its host is mapped to a channel: Slack, search engines, X, GitHub, Discord, YouTube, email, and the Hack Club site have names. Any other site is its host, such as `news.ycombinator.com`. No referrer, or this site, is `direct`.
3. **The guide a first visit starts on.** A first visit to `/stardance` or `/clubs` with no tag comes from that guide. Its medium is the referring site, or `direct`.

The server accepts the browser's channel names, and other values of up to 40 lowercase letters, digits, dots, dashes and underscores. Anything else is `other`. Once a column holds 40 distinct values of its own on a day, any new value that day is also `other`, so junk cannot grow the tables.

### First touch and last touch

- **First touch** is the first arrival this browser made. It is set once and never changes. A browser that used the site before counting began has an unknown first touch.
- **Last touch** is the latest arrival that was not direct. A typed address, or a bookmark, keeps the source before it. For a guide, the last touch is taken when the browser opens that guide. For a signup, it is taken when the browser signs up.

### Tagging links

Tag links that you share, so that a reader's arrival names its own source:

```
https://playground.hackclub.com/clubs?utm_source=clubs&utm_medium=email&utm_campaign=launch
https://playground.hackclub.com/?utm_source=slack&utm_medium=announcement&utm_campaign=lock-in
```

Use short lowercase words for each value. Do not put a person's name, an email address, or a school's name in a tag. Do not tag links between pages of this site, because a tag on an internal link replaces the real source.

## Time spent

Engaged time counts while the tab is visible, and while the reader has scrolled, moved the pointer, touched, or typed in the last 30 seconds. A tab that comes back into view counts as activity. Inside the old desktop's `guide.txt` window, the guide counts only after the reader acts in it, because the desktop can reopen the window unread. Time adds up over every visit, and falls into buckets: under 2 minutes, 2 to 5, 5 to 10, 10 to 20, 20 to 40, 40 to 60, and 60 minutes or more.

## Accuracy and limits

- **Readers are browsers.** One person on two devices counts twice. Clearing site data, or private browsing that ends, starts a new browser. Where `localStorage` is blocked, no journey is reported, because nothing could stop the same reader from counting again.
- **"Stopped here" means stopped so far.** A reader who comes back later moves on to a later stage. Recent days will show more readers stopped early than will stay so.
- **Days are start days.** The days on the guide panel select readers by the day they started the guide. A reader who started before counting began is not in the journey counts.
- **Time is a floor.** A reader who follows along in Godot with the guide open, without touching it, stops counting after 30 seconds. A tab left open beside activity elsewhere does not count.
- **Delivery.** Reports go every 15 seconds while the page is open, and as a beacon when it hides or closes. A report that fails while the page is open is sent again. A beacon lost as the page closes, usually offline, is not: that reader is then missing from the stages and minutes the lost report added, which can look like a stop where the server last heard. A report delivered twice counts twice. Both are rare.
- **Forged reports.** Anyone can send a report. The rate limit, the guard on values, and counts that only go up bound the damage. A forged report can add counts, but cannot remove them. The admin math clamps any difference that would come out negative to zero.
- **"More stop here"** marks a section only where at least 5 readers of the chosen source stopped, and a two-proportion test at 95% says the gap is not chance. With about 20 sections, about 1 mark in 20 can still be chance.
- **Signups before counting** have no source. Nothing saved can recover one.
