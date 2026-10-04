import Foundation

/// Which side of the match.
public enum TeamSide: String, Codable, Sendable, Equatable, CaseIterable {
    case home, away

    public var other: TeamSide { self == .home ? .away : .home }
    public var title: String { self == .home ? "Home" : "Away" }
}

/// What happened in a match, in the order it happened.
///
/// The log is the only input. The clock, the score, the report and the stats
/// are all *derived* from these events, so a relaunch, a JSON round-trip or a
/// sync from the watch can never disagree with itself. See SCOPE.md, "the
/// model never advances".
public struct MatchEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Wall-clock time. The match clock is computed from these, never ticked.
    public var at: Date
    public var kind: Kind

    public init(id: UUID = UUID(), at: Date, kind: Kind) {
        self.id = id
        self.at = at
        self.kind = kind
    }

    public enum Kind: Codable, Sendable, Equatable {
        // What the clock folds on.
        case kickOff(half: Int)
        case halfEnd(half: Int)
        case clockPaused
        case clockResumed
        case fullTime
        /// Added time *announced* for a half — recorded when the referee
        /// signals it, counted only when the clock passes the half length.
        case addedTime(half: Int, seconds: TimeInterval)

        // What the referee records. The clock deliberately ignores these;
        // the score, cards and report read them (P1).
        case goal(side: TeamSide, scorer: UUID?)
        case ownGoal(side: TeamSide, scorer: UUID?)
        case disallowedGoal(side: TeamSide)
        case yellowCard(side: TeamSide, player: UUID)
        case secondYellow(side: TeamSide, player: UUID)
        case redCard(side: TeamSide, player: UUID)
        case sinBin(side: TeamSide, player: UUID, minutes: Int)
        case sinBinEnd(side: TeamSide, player: UUID)
        case substitution(side: TeamSide, off: UUID, on: UUID)
        case note(String)
    }
}

extension MatchEvent.Kind {
    /// The kinds the clock folds on. Incidents deliberately are not here, so
    /// a card can never move the clock an inch.
    public var isClockRelevant: Bool {
        switch self {
        case .kickOff, .halfEnd, .clockPaused, .clockResumed, .fullTime, .addedTime:
            return true
        default:
            return false
        }
    }
}
