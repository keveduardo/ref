# Ref — scope, decisions, and the way there

Written 2026-10-04, from the session that created the repo. `README.md` is the
layout and current state; this file is the plan.

## What this is

A soccer referee app for iPhone and Apple Watch, built for Kevin himself: the
**watch runs the match** (clock, score, cards, subs, sin bins) and the **phone
sets up before and reports after**. On match day the referee picks the match on
the phone and sends it to the watch; incidents are recorded on the watch with
no phone and no internet; the report and the season record are read back on the
phone.

The app is its own thing throughout: its own name, icon, code and copy.

The estate has already solved the hard part: **Apple Watch apps ship from this
box with no Mac**. Rowing and Swim are built by XcodeGen on a GitHub macOS
runner, signed through an App Store Connect API key and uploaded to TestFlight;
a `render` job screenshots the real SwiftUI in a simulator. Ref is the same
shape, plus a real iPhone app instead of a stub container.

## Decisions (Kevin, 2026-10-04)

| Decision | Answer |
|---|---|
| Repo home | **Standalone `~/dev/ref`** — its own private GitHub repo, its own CI |
| Phone app | **Full companion** — teams/squads, match setup, history, report, share |
| Distribution | **TestFlight, unlisted** — like Swim/Soccer/Glosa |
| Fitness data | **In v1** — HealthKit workout: heart rate, energy, GPS distance |
| Sport | Soccer only; the engine stays period-shaped for later sports |

Identifiers (renameable until registered): bundle ids `com.brisaloca.ref` and
`com.brisaloca.ref.watchkitapp`, App Store name **"Brisaloca RefTime"** (Kevin,
2026-10-04 — "RefTime" alone was taken; first drafted as "Brisaloca Ref"), device name "Brisaloca RefTime" ✅ created 2026-10-04. The repo, targets
and RefKit keep the short internal name Ref.

## What v1 is

**Watch app (standalone on the pitch — the phone stays in the bag):**

- **Start**: today's match sent from the phone, or Quick Start (Home vs Away)
- **Live**: big wall-clock-anchored timer, score, period, added time as
  `45:00 +2:10`; readable in always-on/dim mode; every incident in ≤3 taps
  with a haptic
- **Record**: Goal (scorer number), Yellow (a second one is recorded as a
  second yellow), Red, Substitution, Sin bin (countdown + a buzz when the
  player may return), added time (+1' per tap), note; **Undo** for any of
  them, and **Resume** for a half ended by mistake
- **Alarms** on the wrist, each its own rhythm: the half's length reached,
  the announced added time used up, a sin bin over
- Half-time timer, End match, summary. No phone, no network needed; a
  mid-match crash or reboot resumes (state is flushed on every event)

**iPhone app:** teams & squads; create a match (teams, competition, half
length, count-up/countdown, sin bin) → **Send to watch**; matches history with
the report (timeline by minute, HR avg/max, distance) and share-as-text;
season stats; settings.

**v1 non-goals**: multi-sport, live phone mirroring during a match, heatmaps,
PDF export, cloud sync, card reason codes, GotSport import.

## Architecture

```
RefKit/            pure Swift package (Foundation only) — the whole engine,
                   tested by `swift test` on Linux
Apps/Ref/          one XcodeGen project: Ref (iOS, real UI) + Ref Watch App
                   (watchOS 11, companion, HealthKit), embedded at
                   Ref.app/Watch/; one archive, one App Store record
tools/ci/          due.mjs (weekly TestFlight expiry) + the ASC helpers
.github/workflows/ref.yml   kit / due / build / ship / render
```

**The model never advances.** The match is a list of events with wall-clock
dates; the clock, score, report and stats are folded from it at ask time. So a
relaunch, a sync merge or a view that slept can never disagree with itself. The
clock face is `text(at: now)` — main field capped at the half length, the
overrun in the `+M:SS` field.

**Sync** is WatchConnectivity only: `updateApplicationContext` for the match
assignment (phone → watch), `transferUserInfo` for finished matches
(watch → phone). **Health**: the watch runs an `HKWorkoutSession` (`.soccer`,
outdoor) for heart rate and energy, plus `CLLocationManager` +
`HKWorkoutRouteBuilder` for distance; the metrics are frozen into the match
record, so the phone needs no Health permission. The running session is also
what keeps the app alive with the wrist down.

**The concurrency pattern is Swim's** (`Apps/Swim/Sources/SwimSession.swift` in
brisaloca-ios): `@MainActor @Observable` classes, `nonisolated` delegate
methods, only Sendable values crossing the hop.

## Phases

| # | What | Verified by |
|---|---|---|
| **P0** ✅ | Repo + CI; RefKit clock with tests; hello screens both apps; delegate skeletons for WCSession/HealthKit/CLLocation | kit/build/render jobs green — the build job asserts the companion shape |
| **P1** ✅ | The engine: events, score derivation, sin-bin expiry, report, JSON store, stats, sync payloads | 41 tests, `swift test` on Linux, on every push |
| **P2** ✅ | Watch UI: Start → Live → record flows → HalfTime → Summary; haptics; dim mode | the render job's screenshots |
| **P3** ✅ | Phone UI: Matches, MatchSetup, Teams, MatchDetail + share, Stats, Settings | the render job's screenshots |
| **P4** ✅ | Sync + HealthKit: WCSession both ways, workout session, GPS distance | compiles and asserts in CI; the *device* proof is the first real match (P5) |
| **P0.5** ✅ | Bundle id registered, app record "Brisaloca RefTime", Admin API key, the first signed upload | Build 22 processed VALID, 2026-10-04 — Apple accepted the pairing |
| **P4.5** ✅ | From a full read of both apps: undo (`.voided` events — the log stays append-only), resume a half ended by mistake, alarms (half length, added time, sin bin over), the sin bin length and quick-start defaults actually reaching the watch, the phone's finished-match handler wired before any view, workout recovery after a crash | 54 tests; CI build; render. Alarms with the wrist down: P5 |
| **P5** | Ship v1: icon, listing notes, `ship` → TestFlight; install on Kevin's iPhone + watch | a real match refereed with it |
| **P6** | Whatever that match teaches | his feedback |

## Next, as Kevin asked for it (2026-10-04, after installing build 22)

Done the same day: AYSO 10U/12U/14U girls/boys presets; half-time buzz
(default 5 min); sin bins removed from the UI; steps and HealthKit distance;
quick create (blank teams are Home/Away placeholders) and an Edit screen for
upcoming matches (names, short names, colours, swap sides, clock).

Still to build, in this order:

1. **Pitch-diagram heatmap** (Kevin chose the fullest option). The watch
   keeps the route (it already records it, for distance) and saves it to
   Health as an `HKWorkoutRoute`, so Fitness shows the map. The referee marks
   the field once, by tapping at the centre spot facing one goal before
   kick-off, which gives the origin and the axis. RefKit projects the route onto
   a normalised 100 × 64 pitch, pure and tested, and computes time per third,
   diagonal coverage, distance per half, top speed and sprint count. The
   route goes to the phone by `transferFile`, since it is too big for user
   info, and the phone draws the heatmap on a pitch.
2. **Optional sign-in: Sign in with Apple or Google, for backup and sync.**
   The app stays fully usable signed out. It needs a small Worker with D1
   for the backup (read `~/dev/brisaloca-home/API-TOKENS.md` before any
   token), a Google OAuth client (Kevin, Google Cloud console), and the Sign
   in with Apple capability on `com.brisaloca.ref`. Apple requires Sign in
   with Apple whenever Google sign-in is offered (guideline 4.8), and a
   delete-account button when accounts exist (5.1.1(v)).
3. **Schedule sync from CGI Sports** (AYSO Region 34, cgisports.com/ref/5524).
   Researched 2026-10-04: it has **no calendar feed and no API** (its own
   feature list), the region's public view is off, and the schedule is
   behind a login. Its "Game reminder" emails are one field per line, though.
   ✅ **Paste reminder email** (build 31): `ScheduledGame` in RefKit parses
   them, the division maps to the AYSO preset, and the game id becomes the
   match id. Still to do: hands-off import. With sign-in (item 2), the user
   gets a forwarding address on Cloudflare Email Routing; a Gmail filter
   forwards `from:noreply@cgisports.com` to it, and a Worker parses and syncs.
   A share extension (Mail → Share → RefTime) is a cheaper middle step.
   Reminders arrive a day or two ahead, so this fills the near term, not a
   whole season.

4. **App Store submission readiness**: a privacy manifest
   (`PrivacyInfo.xcprivacy`, UserDefaults reason CA92.1), a privacy policy
   page (required for HealthKit), a support URL, the privacy "nutrition
   label" (Data Not Collected while everything is on-device; it changes with
   sign-in), 6.9" iPhone and watch screenshots from the render job, and
   review notes.

## Kevin's errands (any time after P0 — all website, one morning)

1. **Mint an App Store Connect API key** — developer.apple.com → Users and
   Access → Integrations → Team Keys → **+**, role **Admin** (App Manager cannot
   use cloud signing — HANDOFF trap 7), download
   the `.p8` **once**. ⚠️ Mobile Safari's download does not work — a desktop
   browser does (the lesson already in brisaloca-ios `APPLE-ACCOUNT.md`). Then
   hand over Key ID + Issuer ID; the three repo secrets follow
   (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`).
2. **Create the app record** — App Store Connect → Apps → **+** → iOS → bundle
   `com.brisaloca.ref`, name "Brisaloca RefTime" ✅ created 2026-10-04, SKU `REF-1`, English (U.S.).
   The API cannot create records; this one is always the website.
3. **HealthKit capability** on the watch bundle id is switched on by automatic
   signing at the first signed build (how Swim's Shallow Depth was). If it
   isn't, from here:
   `node tools/ci/enable-capability.mjs healthkit com.brisaloca.ref.watchkitapp`
   — then archive again.

## Risks / unknowns

1. **Swift 6 concurrency across four NSObject delegates** — the pattern is
   Swim's, and P0 compiles real skeletons so it is settled before any UI.
2. **Always-on display** — every clock face is driven from
   `TimelineView(.periodic)` + `now`; sin-bin haptics compare `now`, never a
   `Timer` (timers coalesce while dimmed).
3. **GPS distance** is the least-proven piece; it degrades to "—" and never
   blocks the match. No `allowsBackgroundLocationUpdates` (it terminates an app
   without the `location` background mode; the workout keeps us alive).
4. **A match is the only copy of a match** — the in-progress match is rewritten
   on every event and the clock rebuilt from the log at launch.
5. **XcodeGen details** (the WK `INFOPLIST_KEY`s, a companion app on a
   standalone watch simulator) are source-verified but only CI can prove them —
   P0's assertions and render job do exactly that.
6. TestFlight builds live 90 days; the weekly `due` job rebuilds before they
   lapse. GitHub macOS minutes bill 10× on private repos — the loop is
   "push → CI renders", never a local build.
