# HANDOFF — where Ref stands, and the way in

Written 2026-10-04 by the session that built P0–P4. Read this first, then
`README.md` (layout and current state) and `SCOPE.md` (the plan and the
decisions behind it — including the phase table this file mirrors).

## Where this stands

| | State |
|---|---|
| Repo | `~/dev/ref` = `keveduardo/ref`, private. Commits go straight to `main`; push after committing. |
| The engine | `RefKit` — 54 tests, green on this box: `swift test --package-path RefKit` |
| The apps | The watch UI and the phone app compile in CI on every push; the `build` job also asserts the companion shape (watch app inside `Ref.app/Watch/`, the WK pairing, equal `CFBundleVersion`s). |
| The screens | `renders/` — the `render` job's screenshots as a README GitHub renders on a phone. Snapshots, replaced in place. |
| Signed / uploaded | **Nothing.** No TestFlight build exists and no match has been refereed with it. |
| The gate | Kevin's three website errands (below). Nothing else blocks the first build. |

## The next action, exactly

**Kevin — one morning, all on the website.** Claude cannot do these through
Claude in Chrome: on 2026-10-04 auto mode refused both minting the key (as a
secret-store write) and opening New App. They are Kevin's clicks.

1. **Mint an App Store Connect API key** — developer.apple.com → Users and
   Access → Integrations → **Team Keys → +**, role **App Manager**, then
   download the `.p8` **once**. ! Mobile Safari's download silently does
   nothing; it wants a desktop browser (learned the hard way on 2026-09-22).
   Hand back: the **Key ID**, the **Issuer ID**, and where the `.p8` lives.
2. **Create the app record** — App Store Connect → **Apps → + → New App** →
   iOS → bundle `com.brisaloca.ref`, name "Brisaloca Ref", SKU `REF-1`,
   English (U.S.). The API cannot create records; this one is always the
   website. ! The Bundle ID menu lists only *registered* ids, and nothing
   has registered this one yet. If it is missing, first:
   developer.apple.com → Certificates, IDs & Profiles → **Identifiers → +**
   → App IDs → App → Explicit, `com.brisaloca.ref`, description "Ref". (The
   watch id is registered by automatic signing at the first archive.)
3. **HealthKit capability** on `com.brisaloca.ref.watchkitapp` — automatic
   signing usually switches it on at the first signed build. If it does not,
   one command from here (it also retires the stale profile):

       node tools/ci/enable-capability.mjs healthkit com.brisaloca.ref.watchkitapp

**Then, from this box** — set the three repository secrets and ship:

    gh secret set ASC_KEY_ID    -R keveduardo/ref          # paste the Key ID
    gh secret set ASC_ISSUER_ID -R keveduardo/ref          # paste the Issuer ID
    gh secret set ASC_KEY_P8    -R keveduardo/ref < <path to the .p8>

    gh workflow run ref.yml -R keveduardo/ref -f upload=true
    gh run list -R keveduardo/ref --limit 1
    gh run watch <id> -R keveduardo/ref

The `ship` job archives the iOS app (the watch app rides inside it), refuses to
upload an archive that carries no watch app, and sends the build to TestFlight.
Build numbers come from the run number; both bundles share it (ITMS demands it).

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

  Pages screenshotted: watch `start live record halftime summary`, phone
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
7. `xcodegen` regenerates everything under `Generated/`; the entitlements file
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
