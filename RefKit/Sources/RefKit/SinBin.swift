import Foundation

/// Which clock a sin bin runs on. The law question, made explicit rather than
/// accidental: most codes mean *playing* time (the bin pauses with the
/// whistle, at half time too), and that is the default here.
public enum BinClock: String, Codable, Sendable, Equatable, CaseIterable {
    /// Playing time — the bin only burns while the match clock runs.
    case match
    /// Wall time — runs through the break, whatever the whistle is doing.
    case wall
}

/// A temporary dismissal: a player off for N minutes, back when the clock
/// says so. One per incident, ended either by expiry or by `sinBinEnd`.
public struct SinBin: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var side: TeamSide
    public var player: UUID
    public var start: Date
    public var duration: TimeInterval
    public var clock: BinClock

    public init(id: UUID = UUID(), side: TeamSide, player: UUID, start: Date,
                minutes: Int, clock: BinClock = .match) {
        self.id = id
        self.side = side
        self.player = player
        self.start = start
        self.duration = TimeInterval(minutes * 60)
        self.clock = clock
    }

    /// Time left before the player may return, by the bin's own clock.
    public func remaining(at now: Date, clock matchClock: MatchClock) -> TimeInterval {
        let burned: TimeInterval
        switch clock {
        case .wall:
            burned = now.timeIntervalSince(start)
        case .match:
            // Playing time since the bin started — so a bin taken in the last
            // minutes of a half resumes its countdown in the next one.
            burned = matchClock.elapsed(at: now) - matchClock.elapsed(at: start)
        }
        return max(0, duration - burned)
    }

    public func isActive(at now: Date, clock matchClock: MatchClock) -> Bool {
        remaining(at: now, clock: matchClock) > 0
    }

    /// Whether this incident has been closed by an explicit end event.
    public func isEnded(in log: EventLog) -> Bool {
        log.events.contains { event in
            if case .sinBinEnd(let side, let player) = event.kind {
                return side == self.side && player == self.player && event.at >= start
            }
            return false
        }
    }
}

public extension EventLog {
    /// The sin bins in the log, oldest first, each paired with the incident
    /// event that opened it. An explicit `sinBinEnd` closes one early; so does
    /// the clock — `remaining` answers that part.
    func sinBins() -> [SinBin] {
        events.compactMap { event in
            guard case .sinBin(let side, let player, let minutes) = event.kind else { return nil }
            return SinBin(id: event.id, side: side, player: player, start: event.at,
                          minutes: minutes)
        }
    }
}
