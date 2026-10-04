import Foundation

/// How a match's clock is configured. Soccer's adult defaults: two halves of
/// 45 minutes, counting up, each half shown from zero.
public struct ClockConfig: Codable, Sendable, Equatable {
    /// Seconds in one half. Youth matches are shorter.
    public var halfLength: TimeInterval
    /// How many periods. Soccer is two; the shape allows more later.
    public var halves: Int
    /// Count down to the half length, or up from kick-off.
    public var countsDown: Bool
    /// Show each half from zero, or one running total across the match.
    public var display: ClockDisplay

    public init(halfLength: TimeInterval = 45 * 60, halves: Int = 2,
                countsDown: Bool = false, display: ClockDisplay = .perHalf) {
        self.halfLength = halfLength
        self.halves = halves
        self.countsDown = countsDown
        self.display = display
    }

    /// The phone's picker works in whole minutes.
    public init(halfMinutes: Int, halves: Int = 2,
                countsDown: Bool = false, display: ClockDisplay = .perHalf) {
        self.init(halfLength: TimeInterval(halfMinutes * 60), halves: halves,
                  countsDown: countsDown, display: display)
    }

    /// Adult soccer: 2 × 45, counting up.
    public static let adult = ClockConfig()
}

public enum ClockDisplay: String, Codable, Sendable, Equatable, CaseIterable {
    case perHalf, cumulative
}

/// Where the match is — derived from the anchors, never stored.
public enum ClockPhase: Codable, Sendable, Equatable {
    case notStarted
    case running(half: Int)
    case paused(half: Int)
    case halfTime(next: Int)
    case fullTime

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// One continuous stretch of play. `end == nil` means it is still running.
public struct Segment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var half: Int
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), half: Int, start: Date, end: Date? = nil) {
        self.id = id
        self.half = half
        self.start = start
        self.end = end
    }

    /// Seconds of play inside this segment by `now`. The end is clamped to
    /// `now`, so a segment closed by a *later* anchor reads only to the ask.
    public func duration(at now: Date) -> TimeInterval {
        max(0, min(end ?? now, now).timeIntervalSince(start))
    }
}

/// The match clock — computed, never ticked.
///
/// The model is `config` plus the clock anchors; every question is asked with
/// a `now` and answered by folding the anchors up to it. Nothing advances on
/// its own, so a view that was asleep, a relaunch mid-match, a clock that
/// jumped by ten minutes and an event that arrived early all read correctly.
public struct MatchClock: Sendable, Equatable {
    public let config: ClockConfig
    /// Only the clock-relevant events, sorted by (at, id). Incidents and
    /// future anchors are inert: both are filtered or clamped at ask time.
    public let anchors: [MatchEvent]

    public init(config: ClockConfig, anchors: [MatchEvent]) {
        self.config = config
        self.anchors = anchors.sorted { lhs, rhs in
            lhs.at == rhs.at ? lhs.id.uuidString < rhs.id.uuidString : lhs.at < rhs.at
        }
    }

    /// The only way a clock comes to exist: from the log.
    public static func replay(config: ClockConfig, events: [MatchEvent]) -> MatchClock {
        MatchClock(config: config, anchors: events.filter { $0.kind.isClockRelevant })
    }

    // MARK: - Derived state

    /// Seconds of play in one half by `now`.
    public func elapsed(inHalf half: Int, at now: Date) -> TimeInterval {
        fold(at: now).segments
            .filter { $0.half == half }
            .reduce(0) { $0 + $1.duration(at: now) }
    }

    /// Seconds of play across the match by `now` — breaks excluded.
    public func elapsed(at now: Date) -> TimeInterval {
        fold(at: now).segments.reduce(0) { $0 + $1.duration(at: now) }
    }

    /// How far past the half length the clock has run.
    public func overrun(inHalf half: Int, at now: Date) -> TimeInterval {
        max(0, elapsed(inHalf: half, at: now) - config.halfLength)
    }

    /// How much of the half is still to play (zero once it is past).
    public func remaining(inHalf half: Int, at now: Date) -> TimeInterval {
        max(0, config.halfLength - elapsed(inHalf: half, at: now))
    }

    /// Added time as the referee *signalled* it for a half. What the clock has
    /// actually run past is the overrun — usually less, until it catches up.
    public func announcedAdded(half: Int, at now: Date) -> TimeInterval {
        fold(at: now).added[half] ?? 0
    }

    public func phase(at now: Date) -> ClockPhase {
        let state = fold(at: now)
        if let open = state.segments.last, open.end == nil {
            return .running(half: open.half)
        }
        switch state.end {
        case .none: return .notStarted
        case .paused(let half): return .paused(half: half)
        case .halfEnded(let half): return .halfTime(next: half + 1)
        case .finished: return .fullTime
        }
    }

    /// Which half the clock face is showing — the one in play, the one just
    /// ended while the break runs, or the last played one after full time.
    public func currentHalf(at now: Date) -> Int {
        let state = fold(at: now)
        if let open = state.segments.last, open.end == nil { return open.half }
        return state.lastHalf ?? 1
    }

    /// How long the break has been running, while the clock is at half time.
    public func halfTimeElapsed(at now: Date) -> TimeInterval? {
        let state = fold(at: now)
        guard case .halfEnded = state.end,
              let last = state.segments.last, let end = last.end else { return nil }
        return max(0, now.timeIntervalSince(end))
    }

    /// The clock face: "45:00 +2:10" once past the half length, "44:00" when
    /// counting down, "82:30" under a cumulative display. Whole seconds, and
    /// never a negative number.
    public func text(at now: Date) -> String {
        let state = fold(at: now)
        let half = currentHalf(at: now)
        let shown: TimeInterval
        let cap: TimeInterval
        switch config.display {
        case .perHalf:
            shown = state.segments.filter { $0.half == half }.reduce(0) { $0 + $1.duration(at: now) }
            cap = config.halfLength
        case .cumulative:
            shown = state.segments.reduce(0) { $0 + $1.duration(at: now) }
            cap = config.halfLength * Double(half)
        }
        let main = min(shown, cap)
        let over = max(0, shown - cap)
        let face = config.countsDown ? max(0, cap - main) : main
        return ClockFormat.withAdded(ClockFormat.mmss(face), overrun: over)
    }

    // MARK: - The fold

    private struct State {
        var segments: [Segment] = []
        var lastHalf: Int?
        var end: End = .none
        var added: [Int: TimeInterval] = [:]

        enum End: Equatable { case none, paused(Int), halfEnded(Int), finished }
    }

    private func fold(at now: Date) -> State {
        var state = State()
        for event in anchors where event.at <= now {
            switch event.kind {
            case .kickOff(let half):
                closeOpen(&state, at: event.at)
                state.segments.append(Segment(half: half, start: event.at))
                state.lastHalf = half
                state.end = .none
            case .halfEnd(let half):
                closeOpen(&state, at: event.at)
                state.lastHalf = half
                state.end = .halfEnded(half)
            case .clockPaused:
                closeOpen(&state, at: event.at)
                state.end = .paused(state.lastHalf ?? 1)
            case .clockResumed:
                let half = state.lastHalf ?? state.segments.last?.half ?? 1
                state.segments.append(Segment(half: half, start: event.at))
                state.lastHalf = half
                state.end = .none
            case .fullTime:
                closeOpen(&state, at: event.at)
                state.end = .finished
            case .addedTime(let half, let seconds):
                state.added[half, default: 0] += seconds
            default:
                break // incidents do not touch the clock
            }
        }
        return state
    }

    private func closeOpen(_ state: inout State, at date: Date) {
        guard let last = state.segments.last, last.end == nil else { return }
        state.segments[state.segments.count - 1].end = date
    }
}

/// Clock text, by hand — no DateComponentsFormatter, so the same string comes
/// out on every platform, in the app and in the tests alike.
public enum ClockFormat {
    /// "45:00", "0:07" — whole seconds down, seconds always two digits.
    public static func mmss(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The main field plus the overrun: "45:00 +2:10", or the field alone when
    /// nothing has been added.
    public static func withAdded(_ main: String, overrun: TimeInterval) -> String {
        overrun <= 0 ? main : "\(main) +\(mmss(overrun))"
    }
}
