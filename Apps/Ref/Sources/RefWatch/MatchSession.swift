import Foundation
import Observation
import RefKit

/// What the watch is doing, and the only thing that changes it.
///
/// Every mutation goes through here, and every mutation is on disk before the
/// call returns — mid-match the watch holds the only copy of the match, and
/// the rule that keeps a crash from costing the referee their match is "the
/// in-progress match is rewritten on every event" (SCOPE.md).
@MainActor @Observable final class MatchSession {
    private let store: MatchStore

    private(set) var match: Match?

    /// The link to the phone and the two recorders that make the fitness
    /// numbers. One session owns one of each; the live screen reads their
    /// published values.
    let link = WatchLink()
    let workout = WorkoutRecorder()
    let location = LocationRecorder()

    /// Ids of the matches already finished on this watch — so the phone's
    /// list stops offering a match the moment it is played, not when the
    /// phone next answers.
    private(set) var playedIDs: Set<UUID> = []

    private var alarm: Task<Void, Never>?

    /// `recovers` is false only for the render job's fixed screens, which
    /// must never start a workout in the simulator.
    init(store: MatchStore = MatchStore(directory: MatchSession.containerDirectory),
         recovers: Bool = true) {
        self.store = store
        // A match left in progress by a crash or a flat battery is still here.
        match = try? store.current()
        playedIDs = Set(((try? store.all()) ?? []).map(\.id))
        guard recovers, let match else { return }
        switch match.clock.phase(at: Date()) {
        case .notStarted:
            break
        case .fullTime:
            // Full time was blown but the crash came before the record was
            // saved and sent — finish that now, or "Done" would lose it.
            if !playedIDs.contains(match.id) {
                Task { await finishMatch() }
            }
        default:
            // …and its workout, unless the crash took that. Without a running
            // workout the app is suspended the moment the wrist drops, and
            // the alarms never fire.
            Task {
                await workout.recover()
                location.start()
            }
            replanAlarms()
        }
    }

    static var containerDirectory: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return base.appendingPathComponent("Ref", isDirectory: true)
    }

    // MARK: - Where we are

    enum Stage: Equatable { case home, ready, live, halfTime, summary }

    var stage: Stage {
        guard let match else { return .home }
        switch match.clock.phase(at: Date()) {
        case .notStarted: return .ready
        case .running, .paused: return .live
        case .halfTime: return .halfTime
        case .fullTime: return .summary
        }
    }

    var clock: MatchClock {
        match?.clock ?? MatchClock.replay(config: .adult, events: [])
    }

    var score: Score { match?.score ?? Score() }

    // MARK: - Starting

    /// The phone's matches still to be played.
    var offers: [MatchSetup] {
        link.assignments.filter { !playedIDs.contains($0.id) }
    }

    /// Quick start: two teams to be named on the phone later, the phone's
    /// default half length and break, kick-off waiting.
    func startQuick() {
        let defaults = link.defaults
        assign(Match(setup: MatchSetup(
            home: .placeholder(.home),
            away: .placeholder(.away),
            clock: ClockConfig(halfMinutes: defaults.halfMinutes, countsDown: true),
            halfTimeMinutes: defaults.halfTimeMinutes)))
    }

    /// Take on a match — the phone's assignment, or quick start.
    func assign(_ match: Match) {
        self.match = match
        persist()
    }

    /// Ask for Health and location once, before the match — a system sheet at
    /// kick-off is the worst moment for one. A refusal costs the report's
    /// numbers, never the match.
    func requestHealthAccess() async {
        await workout.requestAccess()
        location.requestAccess()
    }

    func discard() {
        match = nil
        try? store.clearCurrent()
        replanAlarms()
    }

    // MARK: - The clock

    func kickOff() {
        let now = Date()
        append(.kickOff(half: 1))
        workout.start(at: now)
        location.start()
    }

    func endHalf() { append(.halfEnd(half: halfAtNow)) }

    func startNextHalf() { append(.kickOff(half: halfAtNow + 1)) }

    func fullTime() {
        append(.fullTime)
        Task { await finishMatch() }
    }

    /// Full time, all the way through: the workout is saved to Health, the
    /// distance is summed, both are frozen into the record, and the record
    /// goes to the phone's shelf — here, and over the link when it can.
    private func finishMatch() async {
        guard var current = match else { return }
        playedIDs.insert(current.id)
        let gps = location.stop()
        let route = SyncPayload.Route.thinned(GeoDistance.filtered(location.points))
        // The route goes into the Health workout too, so Fitness shows the map.
        var metrics = await workout.finish(route: route) ?? MatchMetrics()
        // HealthKit's distance (GPS plus stride calibration) when it has one;
        // our own GPS sum when it does not.
        if (metrics.distanceMeters ?? 0) <= 0 {
            metrics.distanceMeters = gps
        }
        if metrics != MatchMetrics() {
            current.metrics = metrics
        }
        // ! Saving the workout takes a moment, and "Done" may have been
        // tapped meanwhile — the record is still saved and sent, but the
        // summary is not put back on a screen the referee already left.
        if match?.id == current.id {
            match = current
        }
        try? store.save(current)
        try? store.clearCurrent()
        link.send(current)
        if !route.isEmpty {
            link.send(SyncPayload.Route(matchID: current.id, points: route))
        }
    }

    // MARK: - The field

    /// "Mark field": the centre spot and the way the referee faces, from the
    /// newest GPS fix and compass reading. False when the fix is not good
    /// enough yet. Without a compass the centre alone is kept (`marked`
    /// false), and the phone takes the field's direction from the route.
    @discardableResult
    func markField() -> Bool {
        guard var current = match,
              let fix = location.latestFix, fix.accuracy > 0, fix.accuracy <= 20 else { return false }
        let heading = location.latestHeading
        guard heading != nil || !location.compassAvailable else { return false }
        current.pitch = PitchFrame(latitude: fix.latitude, longitude: fix.longitude,
                                   bearing: heading ?? 0, marked: heading != nil)
        match = current
        persist()
        return true
    }

    /// One tap, one announced minute.
    func tapAddedTime() { append(.addedTime(half: halfAtNow, seconds: 60)) }

    private var halfAtNow: Int { clock.currentHalf(at: Date()) }

    // MARK: - Incidents

    enum Card { case yellow, red }

    func goal(side: TeamSide, scorer: PlayerRef?) {
        append(.goal(side: side, scorer: scorer))
    }

    /// A yellow to a player already booked is recorded as the second yellow
    /// it is — the report then shows the sending-off.
    func card(_ card: Card, side: TeamSide, player: PlayerRef) {
        switch card {
        case .yellow:
            append(match?.events.hasYellow(side: side, player: player) == true
                   ? .secondYellow(side: side, player: player)
                   : .yellowCard(side: side, player: player))
        case .red:
            append(.redCard(side: side, player: player))
        }
    }

    // MARK: - Taking it back

    /// The newest incident still standing, with the report's own words for
    /// it — what the record menu offers to undo.
    var lastUndoable: (event: MatchEvent, text: String)? {
        guard let match, let event = match.events.lastUndoable,
              let text = MatchReport.text(for: event.kind, in: match) else { return nil }
        return (event, text)
    }

    func undo(_ event: MatchEvent) {
        append(.voided(event.id))
    }

    /// The half end the break is running from — "Resume" takes it back, and
    /// the clock carries on as though the whistle had never gone.
    var resumableHalf: Int? {
        guard let event = match?.events.lastHalfEnd,
              case .halfEnd(let half) = event.kind else { return nil }
        return half
    }

    func resumeHalf() {
        guard let event = match?.events.lastHalfEnd else { return }
        append(.voided(event.id))
    }

    func substitution(side: TeamSide, off: PlayerRef, on: PlayerRef) {
        append(.substitution(side: side, off: off, on: on))
    }

    // MARK: - Plumbing

    private func append(_ kind: MatchEvent.Kind) {
        guard var current = match else { return }
        current.events.append(MatchEvent(at: Date(), kind: kind))
        match = current
        persist()
    }

    private func persist() {
        replanAlarms()
        guard let match else { return }
        try? store.saveCurrent(match)
    }

    // MARK: - Alarms

    /// Sleep until the next moment the referee must feel — the half's length,
    /// the added time used up, the break over — buzz, and plan again. Planned
    /// afresh after every event, because every event can move them (RefKit's
    /// `upcomingAlerts` is a projection from now). With the wrist down this
    /// only runs because the workout session keeps the app alive; without
    /// Health access the app is suspended and the face is the only alarm.
    private func replanAlarms() {
        alarm?.cancel()
        alarm = nil
        guard let match, let next = match.upcomingAlerts(after: Date()).first else { return }
        alarm = Task { [weak self] in
            let wait = next.at.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled, let self else { return }
            await Haptics.alert(next.kind)
            guard !Task.isCancelled else { return }
            self.replanAlarms()
        }
    }
}

#if DEBUG
extension MatchSession {
    /// A session wound to a given moment, in a throwaway store — for the
    /// `render` job's screenshots. Never touches the real container, and it
    /// backdates the events so each page shows a plausible face rather than
    /// 0:00.
    static func showing(_ page: String) -> MatchSession {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ref-render-\(page)-\(UUID().uuidString)", isDirectory: true)
        let session = MatchSession(store: MatchStore(directory: dir), recovers: false)
        let now = Date()
        /// Whole seconds, so an older type-checker cannot read the arithmetic
        /// as an Int (the Swift 6.0 trap from the kit's tests).
        func event(_ ago: Int, _ kind: MatchEvent.Kind) -> MatchEvent {
            MatchEvent(at: now.addingTimeInterval(TimeInterval(-ago)), kind: kind)
        }

        let home = Team(name: "Madrid", abbreviation: "RMA", color: .white)
        let away = Team(name: "Arsenal", abbreviation: "ARS", color: .red)
        let squad = { (team: Team) in
            Squad(team: team, players: (1...11).map { Player(name: "Player \($0)", number: $0) })
        }

        let events: [MatchEvent]
        switch page {
        case "halftime":
            events = [
                event(48 * 60, .kickOff(half: 1)),
                event(36 * 60, .goal(side: .away, scorer: PlayerRef(number: 11))),
                event(10 * 60, .goal(side: .home, scorer: PlayerRef(number: 9))),
                event(3 * 60, .addedTime(half: 1, seconds: 120)),
                event(3 * 60, .halfEnd(half: 1)),
            ]
        case "summary":
            events = [
                event(110 * 60, .kickOff(half: 1)),
                event(98 * 60, .goal(side: .home, scorer: PlayerRef(number: 9))),
                event(70 * 60, .yellowCard(side: .away, player: PlayerRef(number: 7))),
                event(62 * 60, .addedTime(half: 1, seconds: 120)),
                event(62 * 60, .halfEnd(half: 1)),
                event(47 * 60, .kickOff(half: 2)),
                event(20 * 60, .yellowCard(side: .home, player: PlayerRef(number: 4))),
                event(12 * 60, .goal(side: .away, scorer: PlayerRef(number: 11))),
                event(60, .fullTime),
            ]
        default:
            events = [
                event(12 * 60 + 34, .kickOff(half: 1)),
                event(7 * 60, .goal(side: .home, scorer: PlayerRef(number: 9))),
                event(4 * 60, .yellowCard(side: .away, player: PlayerRef(number: 7))),
            ]
        }

        session.assign(Match(setup: MatchSetup(
            home: home, away: away, competition: "Friendly",
            squads: [squad(home), squad(away)]), events: EventLog(events: events)))
        return session
    }
}
#endif
