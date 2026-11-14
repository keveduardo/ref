import Foundation

/// A quick start that was really a scheduled game (2026-11-14). A referee in
/// a hurry taps Quick start instead of the game on the list; the result then
/// sits beside the fixture as "HOM vs AWY", and the fixture stays unplayed.
/// When the quick start's kick-off falls in the scheduled game's window, the
/// two become one: the fixture's teams, crew and competition, with the quick
/// start's clock, events, health numbers and field.
public enum QuickStartFold {
    /// A game may kick off a little early…
    public static let early: TimeInterval = 15 * 60
    /// …and is often late. Later than this, it is more likely the next game.
    public static let late: TimeInterval = 45 * 60

    /// The fixture `quick` most likely was: never started, not on the watch,
    /// its kick-off within `early`/`late` of the quick start's. The nearest
    /// if several; nil when none, or two are equally near.
    public static func target(for quick: Match, among shelf: [Match], onWatch: Set<UUID>) -> Match? {
        guard let started = quick.firstKickOff else { return nil }
        let candidates = shelf.compactMap { match -> (Match, TimeInterval)? in
            guard match.id != quick.id, !match.isFinished, match.events.recorded.isEmpty,
                  !onWatch.contains(match.id), let kickOff = match.setup.kickOff else { return nil }
            let offset = started.timeIntervalSince(kickOff)
            guard offset >= -early, offset <= late else { return nil }
            return (match, abs(offset))
        }.sorted { $0.1 < $1.1 }
        guard let nearest = candidates.first else { return nil }
        if candidates.count > 1, candidates[1].1 == nearest.1 { return nil }
        return nearest.0
    }

    /// The fixture, played: its own id, teams, crew and competition; the
    /// quick start's clock — the events were timed against it — and its
    /// record.
    public static func fold(_ quick: Match, into fixture: Match) -> Match {
        var merged = fixture
        merged.setup.clock = quick.setup.clock
        merged.setup.halfTimeMinutes = quick.setup.halfTimeMinutes
        merged.setup.quarterBreak = quick.setup.quarterBreak
        merged.setup.addedTimeButton = quick.setup.addedTimeButton
        merged.setup.sinBinMinutes = quick.setup.sinBinMinutes
        merged.setup.formatID = fixture.setup.formatID ?? quick.setup.formatID
        // A colour chosen on the watch was chosen looking at the shirts.
        for side in [TeamSide.home, .away] where quick.setup.team(side).color != Team.placeholder(side).color {
            merged.setup.setColor(quick.setup.team(side).color, for: side)
        }
        merged.events = EventLog(events: quick.events.recorded)
        merged.metrics = quick.metrics
        merged.pitch = quick.pitch
        return merged
    }
}

extension Match {
    /// When the first half kicked off — nil before it has.
    public var firstKickOff: Date? {
        events.events.first { event in
            if case .kickOff(half: 1) = event.kind { return true }
            return false
        }?.at
    }
}
