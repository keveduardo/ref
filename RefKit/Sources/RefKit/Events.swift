import Foundation

/// Which side of the match.
public enum TeamSide: String, Codable, Sendable, Equatable, CaseIterable {
    case home, away

    public var other: TeamSide { self == .home ? .away : .home }
    public var title: String { self == .home ? "Home" : "Away" }
}

/// A player as an incident refers to them.
///
/// The number is the primary key on purpose: on the pitch the referee records
/// by shirt number, two taps, and the roster is often unknown. `id` is filled
/// in only when a team sheet exists, and the report prefers a name when the
/// squad lookup finds one.
public struct PlayerRef: Codable, Sendable, Equatable {
    public var id: UUID?
    /// Shirt number. 0 means "not given".
    public var number: Int

    public init(id: UUID? = nil, number: Int = 0) {
        self.id = id
        self.number = number
    }

    public init(_ player: Player) {
        self.init(id: player.id, number: player.number)
    }
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
        case goal(side: TeamSide, scorer: PlayerRef?)
        case ownGoal(side: TeamSide, scorer: PlayerRef?)
        case disallowedGoal(side: TeamSide)
        case yellowCard(side: TeamSide, player: PlayerRef)
        case secondYellow(side: TeamSide, player: PlayerRef)
        case redCard(side: TeamSide, player: PlayerRef)
        case sinBin(side: TeamSide, player: PlayerRef, minutes: Int)
        case sinBinEnd(side: TeamSide, player: PlayerRef)
        case substitution(side: TeamSide, off: PlayerRef, on: PlayerRef)
        case note(String)

        /// Takes back the event with this id — a mis-tap undone on the pitch.
        /// The log stays append-only (so a re-delivered sync still merges by
        /// id); `EventLog.events` simply leaves out the void and its target.
        case voided(UUID)
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

    /// What the referee may take back from the record menu: every incident,
    /// and announced added time. Not the clock's own anchors — a half ended
    /// by mistake is resumed from the break instead (`EventLog.lastHalfEnd`),
    /// and kick-off and full time each have their own deliberate tap.
    public var isUndoable: Bool {
        switch self {
        case .kickOff, .halfEnd, .clockPaused, .clockResumed, .fullTime, .voided:
            return false
        default:
            return true
        }
    }
}
