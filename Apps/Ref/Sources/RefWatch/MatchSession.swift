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

    init(store: MatchStore = MatchStore(directory: MatchSession.containerDirectory)) {
        self.store = store
        // A match left in progress by a crash or a flat battery is still here.
        match = try? store.current()
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

    /// Quick start: two teams to be named on the phone later, the configured
    /// half length, kick-off waiting.
    func startQuick() {
        let halfMinutes = SessionSettings.halfMinutes
        assign(Match(setup: MatchSetup(
            home: Team(name: "Home", abbreviation: "HOM", color: .blue),
            away: Team(name: "Away", abbreviation: "AWY", color: .red),
            clock: ClockConfig(halfMinutes: halfMinutes))))
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
        var metrics = await workout.finish() ?? MatchMetrics()
        metrics.distanceMeters = location.stop()
        if metrics != MatchMetrics() {
            current.metrics = metrics
        }
        match = current
        try? store.save(current)
        try? store.clearCurrent()
        link.send(current)
    }

    /// One tap, one announced minute.
    func tapAddedTime() { append(.addedTime(half: halfAtNow, seconds: 60)) }

    private var halfAtNow: Int { clock.currentHalf(at: Date()) }

    // MARK: - Incidents

    enum Card { case yellow, red }

    func goal(side: TeamSide, scorer: PlayerRef?) {
        append(.goal(side: side, scorer: scorer))
    }

    func card(_ card: Card, side: TeamSide, player: PlayerRef) {
        switch card {
        case .yellow: append(.yellowCard(side: side, player: player))
        case .red: append(.redCard(side: side, player: player))
        }
    }

    func sinBin(side: TeamSide, player: PlayerRef) {
        append(.sinBin(side: side, player: player, minutes: SessionSettings.sinBinMinutes))
    }

    func substitution(side: TeamSide, off: PlayerRef, on: PlayerRef) {
        append(.substitution(side: side, off: off, on: on))
    }

    /// Sin bins still running, with the time each player has left.
    func activeBins(at now: Date) -> [(bin: SinBin, remaining: TimeInterval)] {
        guard let match else { return [] }
        let clock = match.clock
        return match.events.sinBins()
            .filter { !$0.isEnded(in: match.events) }
            .map { ($0, $0.remaining(at: now, clock: clock)) }
            .filter { $0.1 > 0 }
    }

    // MARK: - Plumbing

    private func append(_ kind: MatchEvent.Kind) {
        guard var current = match else { return }
        current.events.append(MatchEvent(at: Date(), kind: kind))
        match = current
        persist()
    }

    private func persist() {
        guard let match else { return }
        try? store.saveCurrent(match)
    }
}

/// The watch's settings, mirrored from the phone's (P3/P4). The defaults are
/// the adult game: 45-minute halves, ten-minute sin bins.
enum SessionSettings {
    static var halfMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "ref.halfMinutes")
        return stored == 0 ? 45 : stored
    }

    static var sinBinMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "ref.sinBinMinutes")
        return stored == 0 ? 10 : stored
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
        let session = MatchSession(store: MatchStore(directory: dir))
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
                event(2 * 60, .sinBin(side: .away, player: PlayerRef(number: 7), minutes: 10)),
            ]
        }

        session.assign(Match(setup: MatchSetup(
            home: home, away: away, competition: "Friendly",
            squads: [squad(home), squad(away)]), events: EventLog(events: events)))
        return session
    }
}
#endif
