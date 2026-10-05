# HANDOFF — where Ref stands, and the way in

Written 2026-10-04 by the session that built P0–P4. Read this first, then
`README.md` (layout and current state) and `SCOPE.md` (the plan and the
decisions behind it — including the phase table this file mirrors).

## Where this stands

| | State |
|---|---|
| Repo | `~/dev/ref` = `keveduardo/ref`, **public** since 2026-10-04 (Kevin's call, so Actions are free; Mac minutes had billed 10× while it was private). Nothing secret is in it: keys live in repo secrets and `~/.config/appstoreconnect`. Keep it so, and keep real people's names out of the test fixtures. The workflow has no `pull_request` trigger, so a fork can never reach the secrets. Commits go straight to `main`; push after committing. |
| The engine | `RefKit` — 54 tests, green on this box: `swift test --package-path RefKit` |
| The apps | The watch UI and the phone app compile in CI on every push; the `build` job also asserts the companion shape (watch app inside `Ref.app/Watch/`, the WK pairing, equal `CFBundleVersion`s). |
| The screens | `renders/` — the `render` job's screenshots as a README GitHub renders on a phone. Snapshots, replaced in place. |
| Signed / uploaded | **Build 22 on TestFlight** (2026-10-04, ship run 37231400733 at `ea029ec`): processed VALID — Apple accepted the companion pairing. Internal group "Household" (every build, Kevin in it). Expires 2027-01-02. **No match has been refereed with it yet.** |
| The gate | None left for shipping. Next is P5's proof: Kevin installs build 22 from TestFlight and referees a real match. |

## The next action, exactly

**Kevin:** open TestFlight on the iPhone, install **RefTime** (build 22) —
the watch app installs with it (Watch app → Available Apps if it does not
appear on its own) — and referee a match with it. First things to check,
because only a real match can prove them: the wrist buzzes at 45:00 and at a
sin bin's end *with the wrist down*; the report reaches the phone; heart rate
and distance are in it.

**Shipping a new build** after a code change, from this box:

    gh workflow run ref.yml -R keveduardo/ref -f upload=true

The secrets are set (`ASC_KEY_ID` = `BDTARG624T`, an **Admin** team key —
trap 7; its `.p8` is in `~/.config/appstoreconnect/private_keys/`). New
builds reach the Household group automatically.

**The weekly `due` job** now has its secrets; trigger it once by hand
(`-f expiry_check=true`) before trusting the schedule.

## What the second session (2026-10-04) changed

A read of both apps end to end, for what would go wrong on the first
Saturday — all fixed, in RefKit with tests where it could be:

- **Undo** is a `.voided(id)` event. `EventLog.recorded` is everything (what
  is stored and sent, still under the `"events"` key); `EventLog.events` is
  the match as it happened, less voids and their targets. Everything
  downstream reads `events`. Nothing is ever deleted, so sync still merges
  by id.
- **Alarms**: `Match.upcomingAlerts(after:)` projects the next buzz from
  now; `MatchSession.replanAlarms()` sleeps until it and re-plans after
  every event. With the wrist down they fire only because the workout
  session keeps the app alive. **Unproven on a device**: that is the first
  thing to check at P5's match.
- **Settings across devices**: the watch cannot read the phone's
  `UserDefaults`. The sin bin length lives in `MatchSetup.sinBinMinutes`,
  and `SyncPayload.Assignment.defaults` carries the quick-start defaults.
- **The phone's `onFinished` is wired in `RefApp.init`**, because a
  background wake can deliver a finished match before any view exists.
- **Crash recovery**: `MatchSession.init` recovers (or restarts) the workout
  for a match in progress, and finishes the save for one already at full
  time. `WorkoutRecorder.recover()` uses `recoverActiveWorkoutSession`. It
  compiles in CI but has never run.

## The server (`server/`)

`reftime.brisaloca.com`, a Worker with D1 `reftime`, serving the privacy and
support pages and the optional backup API. Tests: `cd server && npm test`
(node:sqlite with the real migration). Deploying follows the estate's rules
in ~/.claude/CLAUDE.md: `npm run migrate:remote` as its own command and read
its result, then `npm run deploy`, which runs the guard. It needs no API
token; wrangler's login covers Workers and D1. The app's backup strips
`metrics` and `pitch` before upload. Keep it that way, because the privacy page
promises it.

## The loop this repo runs on

- **A code change**: commit to `main`, push. CI runs `kit` (Linux, `swift test`),
  then `build` (macOS, both schemes, the shape assertions) — on every push that
  touches `Apps/Ref/**`, `RefKit/**`, `tools/ci/**` or the workflow.
- **The screens** (the review loop; there is no Mac and no Simulator here, so
  this is what "seeing it" means):

      gh workflow run ref.yml -R keveduardo/ref -f render=true
      gh run list -R keveduardo/ref --limit 1
      gh run watch <id> -R keveduardo/ref
      gh run download <id> -R keveduardo/ref -n ref-renders -D .renders
      cp .renders/*.png renders/ && git add renders && git commit && git push

  Pages screenshotted: watch `start live home record number halftime summary`, phone
  `matches setup teams detail stats settings` — the lists are in `ref.yml` and
  must match `RenderDemo.Page` in each app.
- **Weekly, unattended**: the `due` job asks App Store Connect whether the live
  TestFlight build is near expiry (the 30-day rule, `tools/ci/due.mjs`).
  TestFlight builds live 90 days; without it the app lapses. It needs the
  secrets, so it stays red until Kevin's errands are done — trigger it by hand
  once with `-f expiry_check=true` before trusting the schedule.
- **The kit is the tested half.** Put logic in `RefKit` and test it here;
  the app targets only ever compile on the runner, so a wrong line in them
  costs a CI round trip.

## Traps (each one cost a round trip; do not relearn them)

1. **Swift 6.0 reads `45 * 60` in a tuple literal as an `Int`** (6.4 reads it
   as a `Double`). The kit's test helpers take whole seconds; keep it that way.
2. **`#expect(x == 5 * 60)` with an Optional left side compares an `Int`** and
   is false at 300.0. Write `TimeInterval(5 * 60)`. (Non-optional left sides
   infer the literal to `Double` correctly.)
3. **A non-Sendable closure formed in a main-actor context keeps that
   isolation.** A stored or escaping closure parameter needs `@MainActor`
   spelled out; Buttons also need `@escaping` on the parameter.
4. **`[String: Any]` from WatchConnectivity cannot cross into a `Task`** —
   pull the `Data` out on the delegate side and send only that.
5. **The build steps print `error:` lines on failure.** A `| tail -40` (the
   pattern copied from brisaloca-ios) swallows them and costs a round trip.
6. The companion watch app **does install and launch standalone on a watch
   simulator** — proven 2026-10-04 by the render job. No pairing dance needed.
7. **The CI key must be Admin, not App Manager.** The first `ship` run
   (2026-10-04, run 37230402141) archived and signed fine, then failed at
   export: `Cloud signing permission error` / `No profiles for
   'com.brisaloca.ref' were found`. Exporting for the App Store uses the
   cloud-managed distribution certificate, which an App Manager key may not
   touch. Rowing's CI key is Admin, which is why Rowing ships.
8. `xcodegen` regenerates everything under `Generated/`; the entitlements file
   is committed (`Entitlements/RefWatch.entitlements`) and referenced by
   `CODE_SIGN_ENTITLEMENTS`, not generated.

## Where things live

- `RefKit/Sources/RefKit/` — `Clock.swift` (the "model never advances" clock),
  `Events.swift` (the log is the only input), `Report.swift`, `Store.swift`
  (current.json on every event — the mid-match crash rule), `Library.swift`
  (teams), `SyncPayload.swift` (versioned envelopes).
- `Apps/Ref/Sources/RefWatch/` — `MatchSession` is the one thing that changes
  the match; `LiveScreen`, `RecordFlow` (≤3 taps), `WorkoutRecorder` /
  `LocationRecorder` (the fitness numbers), `WatchLink`.
- `Apps/Ref/Sources/Ref/` — `PhoneStore` (the shelf), `MatchesScreen`,
  `MatchSetupScreen`, `MatchDetailScreen` (half-grouped timeline), `TeamsScreen`,
  `StatsScreen`, `SettingsScreen`, `PhoneLink`.
- `SCOPE.md` — the plan; `APPSTORE.md` — the listing draft (the record must
  exist before the first upload); `renders/` — the screens.

## Voice, for whoever continues this

Kevin reviews from a phone: give him a link or a screenshot, never a local
build. State what is proven and what is not, in those words — this file and
SCOPE.md are the record, and both are deliberately more careful about the word
"done" than the code is.
