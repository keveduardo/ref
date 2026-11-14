# RefTime — App Store Connect listing

Drafted 2026-10-04, in the shape of `Apps/Swim/APPSTORE.md` in brisaloca-ios.
**The app record exists** (created 2026-10-04 as "Brisaloca RefTime"), but
none of this listing text has been written into it yet, and nothing has been
signed or uploaded. This file is the draft and the place to edit it before sending.

Distribution: **public** (Kevin, 2026-11-13: "Ok for public release"),
released automatically once approved. Planned as Unlisted until then.

---

## App information

| Field | Value |
|---|---|
| Name (record) | Brisaloca RefTime — "RefTime" alone was taken (2026-10-04) |
| Name (on device) | RefTime |
| Bundle id | `com.brisaloca.ref` |
| Watch app | `com.brisaloca.ref.watchkitapp` (companion) |
| SKU | `REF-1` |
| Primary language | English (U.S.) |
| Category | Sports |
| Age rating | 4+ |
| Price | Free |

## Subtitle (30)

Match clock, cards and reports

## Promotional text (170)

The match on your wrist, the paperwork on your phone: a referee's clock with added time, goals and cards in two taps, and the report waiting when you come off.

## Description (4000)

RefTime puts the match on your wrist and the paperwork on your phone.

ON THE WATCH — WHERE THE MATCH HAPPENS
• A referee's clock: count up with added time in its own field, or count down — whichever you run. Pause it for an injury and the alarms wait with it.
• One tap adds a minute of added time as you signal it.
• Goals, yellow and red cards, substitutions and sin bins in two or three taps, by shirt number from your team sheets. A tap on the wrist confirms each one without looking.
• The wrist buzzes when the half is up, when added time runs out, and when half time or a quarter break is over.
• AYSO presets from 7U to 19U fill in half lengths, quarter breaks and whether cards and the score are kept.
• Beach Cup tournament mode sets the half length from the round and age group.
• Change a team's colour mid-match, straight from the watch.
• Records the match as a workout, so your distance and heart rate land in the report and in Fitness.

ON THE PHONE — BEFORE AND AFTER
• Set up a match — teams, colours, kick-off, half length, your crew and whether you're the centre or an assistant — and it's on the watch.
• Referee for an AYSO region on CGI Sports? Sign in and your assignments arrive on their own, crew and all, and follow the assignor's changes.
• After the match: the report minute by minute (45+2′ and all), the score, the distance you covered, your heart rate, a map of where you ran, and a text version to share.
• Season stats: matches, cards and distance, in kilometres or miles.

PRIVATE BY DESIGN
No ads and no tracking. Your matches live on your iPhone and Apple Watch. Signing in with Apple is optional and only backs up your matches and team sheets — never your health data or routes.

## Keywords (100)

referee,soccer,football,whistle,timer,cards,match,AYSO,assistant,linesman,stoppage,added time

## What's New

First version (not shown for a first release).

## App Review information

- Sign in with Apple is optional (Settings › Account): it backs up matches and
  team sheets. Every feature works without an account; no demo account needed.
- CGI Sports sign-in (Settings › Referee schedule) is for referees with an
  account on that site; the rest of the app works without it.
- Health: the watch records the match as a soccer workout. A refusal leaves
  the match fully usable, without distance and heart rate.
- Location: while in use only, to measure distance and draw the route.
- The watch app needs the iPhone app for setup; quick start works on the
  watch alone.

## App Privacy (the questionnaire — website only, the API cannot set it)

Matches `PrivacyInfo.xcprivacy` (2026-11-13). All linked to the user, used for
app functionality only, never tracking — and only when the user signs in:
- Contact info › Email address (Sign in with Apple, if shared)
- Identifiers › User ID
- User content › Other user content (matches and team sheets)
Health and fitness and location are **not** collected: they stay on device.

## Screenshots

From the `render` job of `.github/workflows/ref.yml` — the real SwiftUI in
simulators, three watch screens and six phone screens. Regenerate after UI
changes; the artifacts are also how the screens get reviewed before any build
is shipped.

## Known before submitting

- **The app record does not exist yet** (Kevin, website — the API cannot
  create one).
- **A privacy policy URL** is required for submission. There is no public page
  for RefTime yet; `brisaloca.com` is the obvious host (the other apps' precedent
  to check before inventing one).
- **Unlisted request** after approval.
- **Soccer only** in 1.0; the description deliberately says "the match", not
  "football", so the listing does not need rewriting if a second sport comes.
