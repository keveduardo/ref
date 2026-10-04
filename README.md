# ref

A soccer referee app for iPhone and Apple Watch, in the shape RefSix made
familiar: **the watch runs the match** (clock, score, cards, substitutions,
sin bins) with the phone in the bag, and **the phone sets up before and reports
after**. Built the `~/dev` way — no Mac in the house.

**`SCOPE.md` is the plan** — read that first. This file is the layout and the
current state of the machine.

## Layout

```
RefKit/     shared Swift package: the match engine — the clock, the incident
            log, the score, sin bins, the report. Foundation only, no SwiftUI
            and no HealthKit, so `swift test` runs it on kevg10
Apps/Ref/   the XcodeGen project, two targets: the iPhone app (Sources/Ref)
            and the companion watch app (Sources/RefWatch). Built by Xcode on
            a GitHub macOS runner; the .xcodeproj is generated, never committed
tools/ci/   due.mjs (the weekly TestFlight expiry check) and the ASC helpers,
            copied from brisaloca-ios where they were first written
tools/make-icon.py   draws the app icon into both asset catalogs
```

## What works today (2026-10-04)

- **The engine is real and tested.** `RefKit` holds the clock (wall-clock
  anchored, halves, added time as a separate field, count-up/countdown,
  cumulative display), the incident log, the score, sin bins, the match
  report, the JSON store and the versioned sync payloads — and 38 tests run
  on this box:

      swift test --package-path RefKit

- **The companion shape is proven by CI**, not by hope. The `build` job
  asserts what makes Ref different from Rowing's and Swim's watch-only apps:
  the watch app inside `Ref.app/Watch/`, `WKCompanionAppBundleIdentifier`
  pointing home, no `WKWatchOnly`, and `CFBundleVersion`s that match (ITMS
  refuses a mismatch). Green on the first run, 2026-10-04.
- **The watch UI exists**: the live face (score, clock, added time, running
  sin-bin chips), the two-tap record flows (goal, cards, substitutions, sin
  bins), half time and the summary. The phone UI is next (P3).
- **The `render` job screenshots both apps** in simulators, so the screens
  can be reviewed from a phone.
- **Signing and upload exist but have not run** — the `ship` job needs the
  three App Store Connect secrets, which need Kevin's errands (SCOPE.md). No
  build has been signed or sent to TestFlight yet.

## What is next

P3–P5 in `SCOPE.md`: the phone screens (P3), sync + HealthKit (P4), and the
first TestFlight build (P5 — gated only on the website errands, which can
happen any time).
