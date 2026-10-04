# Ref — App Store Connect listing

Drafted 2026-10-04, in the shape of `Apps/Swim/APPSTORE.md` in brisaloca-ios.
**Nothing here has been written into App Store Connect yet** — the app record
does not exist (SCOPE.md, "Kevin's errands"), and nothing has been signed or
uploaded. This file is the draft and the place to edit it before sending.

Distribution: **Unlisted**, like Swim, Soccer and Español — request at
developer.apple.com/contact/request/unlisted-app once it is submitted; it goes
through the same review.

---

## App information

| Field | Value |
|---|---|
| Name (record) | Brisaloca Ref |
| Name (on device) | Ref |
| Bundle id | `com.brisaloca.ref` |
| Watch app | `com.brisaloca.ref.watchkitapp` (companion) |
| SKU | `REF-1` |
| Primary language | English (U.S.) |
| Category | Sports |
| Age rating | 4+ |
| Price | Free (unlisted) |

## Promotional text (170)

The referee's watch, properly: the clock counts with added time, the score and
cards are two taps each, and the match report is waiting on your phone when
you come off the pitch. No account, no signal needed, nothing leaves the
devices.

## Description (4000)

Ref puts the match on your wrist and the paperwork on your phone.

**On the watch** — where the match happens:
- The clock: 45-minute halves by default (20–45 configurable on the phone),
  counting up with added time in its own field — 45:00 +2:30 — or counting
  down, whichever you run.
- One tap adds a minute of added time, as you signal it.
- Goal, yellow, red, substitution and sin bin in two or three taps. Numbers
  from your team sheets, or 1–18 when you don't have them. A haptic confirms
  every recording without looking.
- Sin bins run on playing time — the countdown pauses at half time, as the
  laws say — and the watch shows who is still off and how long is left.
- Half time and full time are one button each; full time asks first.
- The screen stays readable with your wrist down, and the app keeps running
  through the whole match.

**On the phone** — before and after:
- Teams and squads once; they appear on the watch as numbers.
- Set a match up — competition, teams, kick-off, half length — and it is on
  the watch the next time the two are near each other.
- After the match: the report, minute by minute (45+2' lives in it), the
  score, the distance you covered and your heart rate from the match's own
  workout, and a share sheet for the text version.
- A season's cards seen and given at a glance.

**What it does not do:** no account, no server, no ads, no tracking. Your
matches stay on your devices.

## Keywords (100)

referee,soccer,football,watch,timer,cards,whistle,match,stoppage,sin bin

## What's New

First version.

## App Review information

- No account, no login, no server: everything works offline, and no data
  leaves the devices.
- Health: the watch records the match as a soccer workout so the referee's
  heart rate and energy appear in Fitness. Read/write is requested with the
  standard Health sheet at first launch; a refusal leaves the match fully
  usable.
- Location: only to measure the distance covered during a match. Used while
  the app is in use; a refusal leaves the distance blank.
- `ITSAppUsesNonExemptEncryption` is false (no crypto in the app).
- The app is U.S. English and 4+.

## App Privacy (the questionnaire — website only, the API cannot set it)

- Data collection: **none**.
- Tracking: **none**.
- The privacy manifest in each bundle (`PrivacyInfo.xcprivacy`) declares only
  the UserDefaults required-reason API (CA92.1).

## Screenshots

From the `render` job of `.github/workflows/ref.yml` — the real SwiftUI in
simulators, three watch screens and six phone screens. Regenerate after UI
changes; the artifacts are also how the screens get reviewed before any build
is shipped.

## Known before submitting

- **The app record does not exist yet** (Kevin, website — the API cannot
  create one).
- **A privacy policy URL** is required for submission. There is no public page
  for Ref yet; `brisaloca.com` is the obvious host (the other apps' precedent
  to check before inventing one).
- **Unlisted request** after approval.
- **Soccer only** in 1.0; the description deliberately says "the match", not
  "football", so the listing does not need rewriting if a second sport comes.
