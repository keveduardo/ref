import Foundation

/// The incident log, as a value with its own ordering rules.
///
/// Events are sorted by (at, id) and deduplicated by id, at the door. That is
/// what makes the sync safe: a finished match that arrives from the watch
/// twice merges into the same log, and an event that arrived early takes its
/// place by its wall-clock date rather than by arrival order.
public struct EventLog: Codable, Sendable, Equatable {
    public private(set) var events: [MatchEvent]

    public init(events: [MatchEvent] = []) {
        self.events = []
        self.append(contentsOf: events)
    }

    public mutating func append(_ event: MatchEvent) {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        events.append(event)
        events.sort { lhs, rhs in
            lhs.at == rhs.at ? lhs.id.uuidString < rhs.id.uuidString : lhs.at < rhs.at
        }
    }

    public mutating func append(contentsOf new: [MatchEvent]) {
        for event in new { append(event) }
    }

    public func contains(id: UUID) -> Bool {
        events.contains { $0.id == id }
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
