import Foundation

/// The incident log, as a value with its own ordering rules.
///
/// Events are sorted by (at, id) and deduplicated by id, at the door. That is
/// what makes the sync safe: a finished match that arrives from the watch
/// twice merges into the same log, and an event that arrived early takes its
/// place by its wall-clock date rather than by arrival order.
///
/// Nothing is ever removed. An undo appends a `.voided(id)`, and `events` —
/// what the clock, the score and the report read — leaves out both the void
/// and the event it takes back. `recorded` is everything, and it is what is
/// written to disk and sent.
public struct EventLog: Codable, Sendable, Equatable {
    public private(set) var recorded: [MatchEvent]

    /// The match as it happened: the recorded events, less the voided ones.
    public var events: [MatchEvent] {
        let voided = Set(recorded.compactMap { event -> UUID? in
            if case .voided(let target) = event.kind { return target }
            return nil
        })
        guard !voided.isEmpty else { return recorded }
        return recorded.filter { event in
            if case .voided = event.kind { return false }
            return !voided.contains(event.id)
        }
    }

    /// Stored under the old key, so the file and wire formats are unchanged
    /// for a log with no undo in it.
    private enum CodingKeys: String, CodingKey {
        case recorded = "events"
    }

    public init(events: [MatchEvent] = []) {
        self.recorded = []
        self.append(contentsOf: events)
    }

    public mutating func append(_ event: MatchEvent) {
        guard !recorded.contains(where: { $0.id == event.id }) else { return }
        recorded.append(event)
        recorded.sort { lhs, rhs in
            lhs.at == rhs.at ? lhs.id.uuidString < rhs.id.uuidString : lhs.at < rhs.at
        }
    }

    public mutating func append(contentsOf new: [MatchEvent]) {
        for event in new { append(event) }
    }

    public func contains(id: UUID) -> Bool {
        recorded.contains { $0.id == id }
    }

    // MARK: - Undo

    /// The newest incident still standing — what "Undo" on the watch offers.
    public var lastUndoable: MatchEvent? {
        events.last { $0.kind.isUndoable }
    }

    /// The half end the break is running from, when it is the last thing the
    /// clock did — what "Resume half" takes back. Nil once the next half has
    /// kicked off or the match is over.
    public var lastHalfEnd: MatchEvent? {
        guard let last = events.last(where: { event in
            if case .addedTime = event.kind { return false }
            return event.kind.isClockRelevant
        }), case .halfEnd = last.kind else { return nil }
        return last
    }

    /// Whether this player already has a yellow card standing in this match —
    /// the next one is a second yellow. Matched by squad id when both have
    /// one, by shirt number otherwise; an unnumbered, unnamed player never
    /// matches.
    public func hasYellow(side: TeamSide, player: PlayerRef) -> Bool {
        events.contains { event in
            guard case .yellowCard(let s, let p) = event.kind, s == side else { return false }
            if let a = p.id, let b = player.id { return a == b }
            return p.number > 0 && p.number == player.number
        }
    }
}

/// A match: what the phone set up, and everything that has happened in it.
///
/// `metrics` stays nil until full time — the watch freezes the workout's
/// numbers in once, and the phone never has to ask Health for anything.
public struct Match: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var setup: MatchSetup
    public var events: EventLog
    public var metrics: MatchMetrics?
    /// The field as the referee marked it on the watch before kick-off —
    /// nil when they did not, and the phone works it out from the route.
    public var pitch: PitchFrame?
    /// When the record was first created — history sorts on this, because a
    /// match with no kick-off time is perfectly normal.
    public var createdAt: Date

    public init(id: UUID? = nil, setup: MatchSetup, events: EventLog = EventLog(),
                metrics: MatchMetrics? = nil, createdAt: Date = Date()) {
        self.id = id ?? setup.id
        self.setup = setup
        self.events = events
        self.metrics = metrics
        self.createdAt = createdAt
    }

    public var clock: MatchClock {
        MatchClock.replay(config: setup.clock, events: events.events)
    }

    public var score: Score { Score.from(events) }

    public var report: MatchReport { MatchReport.make(from: self) }

    public var isFinished: Bool {
        if case .fullTime = clock.phase(at: Date()) { return true }
        return false
    }
}
