import Foundation

/// A moment the referee must feel on the wrist without looking: the half's
/// length reached, the announced added time used up, the break over, a player
/// free to return from the sin bin.
public struct MatchAlert: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case halfLength(half: Int)
        case addedTimeUp(half: Int)
        /// The break has run its `MatchSetup.halfTimeMinutes`.
        case halfTimeOver(next: Int)
        case binOver(binID: UUID, side: TeamSide, player: PlayerRef)
    }

    public var at: Date
    public var kind: Kind

    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }
}

extension Match {
    /// The alerts still ahead of `now`, soonest first.
    ///
    /// A projection, not a schedule: it assumes the clock keeps doing what it
    /// is doing now, so it is only right until the next event — which is why
    /// the watch asks again after every one. Playing-time moments are only
    /// projected while the clock runs; a wall-clock sin bin runs through
    /// anything.
    public func upcomingAlerts(after now: Date) -> [MatchAlert] {
        let clock = self.clock
        var alerts: [MatchAlert] = []
        let running = clock.phase(at: now).isRunning

        if case .running(let half) = clock.phase(at: now) {
            let elapsed = clock.elapsed(inHalf: half, at: now)
            let length = clock.config.halfLength
            if elapsed < length {
                alerts.append(MatchAlert(at: now.addingTimeInterval(length - elapsed),
                                         kind: .halfLength(half: half)))
            }
            let added = clock.announcedAdded(half: half, at: now)
            if added > 0, elapsed < length + added {
                alerts.append(MatchAlert(at: now.addingTimeInterval(length + added - elapsed),
                                         kind: .addedTimeUp(half: half)))
            }
        }

        if case .halfTime(let next) = clock.phase(at: now),
           let elapsed = clock.halfTimeElapsed(at: now) {
            let length = TimeInterval(setup.halfTimeMinutes * 60)
            if elapsed < length {
                alerts.append(MatchAlert(at: now.addingTimeInterval(length - elapsed),
                                         kind: .halfTimeOver(next: next)))
            }
        }

        for bin in events.sinBins() where !bin.isEnded(in: events) {
            guard running || bin.clock == .wall else { continue }
            let remaining = bin.remaining(at: now, clock: clock)
            guard remaining > 0 else { continue }
            alerts.append(MatchAlert(at: now.addingTimeInterval(remaining),
                                     kind: .binOver(binID: bin.id, side: bin.side, player: bin.player)))
        }

        return alerts.sorted { $0.at < $1.at }
    }
}
