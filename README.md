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

- **The whole app compiles and its shape is asserted, in CI.** Watch UI and
  phone UI (Swift 6 strict concurrency), the watch↔phone link, and the
  HealthKit workout all build; the `build` job asserts what makes Ref's
  companion watch app different from Rowing's and Swim's watch-only ones —
  the watch app inside `Ref.app/Watch/`, `WKCompanionAppBundleIdentifier`
  pointing home, no `WKWatchOnly`, matching `CFBundleVersion`s.
- **The engine is real and tested** — 41 tests, run on this box on every
  push and by the `kit` job:

      swift test --package-path RefKit

- **Everything is wired end to end**: the phone's match setup travels to the
  watch, the watch runs the match (clock, score, cards, subs, sin bins) with
  no phone and no signal, the match is saved to Health as a workout, and the
  finished record — score, timeline, distance, heart rate — comes back to the
  phone's shelf.
- **The `render` job screenshots both apps** in simulators, so the screens
  can be reviewed from a phone (the artifacts of a `render` run).
- **Signing and upload exist but have not run** — the `ship` job needs the
  three App Store Connect secrets, which need Kevin's errands (SCOPE.md).
  Nothing has been signed or uploaded, and no match has been refereed with
  it yet: the first real match is P5's acceptance test.

## What is next

P0.5–P5 in `SCOPE.md`: the three website errands (the only gate), the first
TestFlight build, then the first real match — after which P6 is whatever
that match teaches.
