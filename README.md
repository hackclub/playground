# playground

The site for **playground**, a Hack Club YSWS: ship a desktop pet, get merch.
froppii runs the program; Armand sponsors it.

The landing page is froppii's [`froppii/playground`](https://github.com/froppii/playground),
ported into Rails. `ship.exe` opens the participant dashboard; `/admin` is the
review, fraud, and fulfillment tool.

## How it works

- **Login:** Hack Club Auth, then Hackatime's OAuth when the account has no Hackatime token yet.
  Anyone can sign up; submitting needs a verified, YSWS eligible identity.
- **Hours:** each pet links any number of Hackatime projects (Lapse syncs into Hackatime).
  Hours move through three stages: **unshipped → pending → approved**.
- **Goals:** stickers, keychain, shirt, marked on one meter. Each is redeemed once, from approved hours.
- **Admin:** review, then fraud, then fulfillment, as queues (one stage across everyone) or on a
  person page (every stage for one participant). Claims, heartbeats, and keyboard shortcuts.
- **Airtable:** Postgres is the write side. `Airtable::SyncJob` copies rows one way every minute.

## Development

```sh
mise install          # Ruby 3.4.10
bundle install
bin/rails db:prepare
bin/rails server
bin/rails test
```

Without OAuth credentials, development uses stand-ins for Hack Club Auth and Hackatime:
log in at `/dev/login?as=participant` (or `unverified`, `red`, `admin`, `froppii`).
They are never loaded outside development and test.
Like a real login, the dev login goes on to link fake Hackatime. Add `&deny=1` to decline that step.
A user whose `hackatime_access_token` is `revoked` gets the answer Hackatime gives a token it no longer takes.

## Configuration

Rails credentials:

| Key | What |
|---|---|
| `hack_club.client_id`, `hack_club.client_secret` | Hack Club Auth OAuth app (HQ official, for the address scope) |
| `hackatime.client_id`, `hackatime.client_secret` | Hackatime OAuth app |
| `airtable.program_token` | Airtable token for the program base |
| `loops.list_id` | Loops list for playground (optional) |
| `github.token` | Raises GitHub's rate limit for gate checks (optional) |

Environment:

| Variable | What |
|---|---|
| `DATABASE_URL` | Orchard Postgres |
| `RAILS_MASTER_KEY` | Decrypts the credentials |
| `APP_HOST` | Defaults to `playground.hackclub.com` |
| `ADMIN_EMAILS` | Comma separated; these accounts become admins at login |
| `AIRTABLE_SYNC` | `1` turns on the Airtable copy |
| `PROGRAM_STARTS_AT`, `PROGRAM_ENDS_AT` | The program window, each `YYYY-MM-DD HH:MM` in US Eastern time. Only Hackatime time from the start up to the end counts. Default `2026-09-25 17:00` to `2026-10-12 09:00`. A bad value stops boot |
| `SOLID_QUEUE_IN_PUMA` | `1` runs jobs inside the web process |
| `PLAUSIBLE_SRC` | The site's script URL from plausible.io, such as `https://plausible.io/js/pa-….js`. Analytics are off when unset |
