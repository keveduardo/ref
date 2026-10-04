import Foundation

/// The score — always derived from the log, never stored, so it cannot drift.
///
/// An own goal counts for the *other* side; a disallowed goal stays on the
/// timeline (it happened, and a report should say so) but never the score.
public struct Score: Codable, Sendable, Equatable {
    public var home: Int
    public var away: Int

    public init(home: Int = 0, away: Int = 0) {
        self.home = home
        self.away = away
    }

    public static func from(_ log: EventLog) -> Score {
        var score = Score()
        for event in log.events {
            switch event.kind {
            case .goal(let side, _):
                score.add(1, to: side)
            case .ownGoal(let side, _):
                score.add(1, to: side.other)
            default:
                break
            }
        }
        return score
    }

    public mutating func add(_ goals: Int, to side: TeamSide) {
        switch side {
        case .home: home += goals
        case .away: away += goals
        }
    }

    public func goals(for side: TeamSide) -> Int {
        side == .home ? home : away
    }

    /// nil when the match is drawn.
    public var winner: TeamSide? {
        home == away ? nil : (home > away ? .home : .away)
    }

    public var text: String { "\(home)–\(away)" }
}
