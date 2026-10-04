import Foundation

/// A team's colour, as a token — not a SwiftUI colour. This package has no
/// SwiftUI on purpose, because it must build and test on Linux; the apps map
/// these to their own palettes.
public enum TeamColor: String, Codable, Sendable, Equatable, CaseIterable {
    case red, blue, green, yellow, orange, purple, black, white
}

public struct Team: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// Up to three letters, for the watch's small screens.
    public var abbreviation: String
    public var color: TeamColor

    public init(id: UUID = UUID(), name: String, abbreviation: String? = nil,
                color: TeamColor = .blue) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation ?? Team.defaultAbbreviation(name)
        self.color = color
    }

    /// "Real Madrid Club" → "RMC", "Arsenal" → "ARS", "FC Barcelona" → "FB".
    public static func defaultAbbreviation(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2 {
            return String(words.prefix(3).compactMap(\.first)).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }
}

public struct Player: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// Shirt number. 0 means "not given" — the watch then records by the
    /// number the referee taps, and 1–99 are all legal.
    public var number: Int

    public init(id: UUID = UUID(), name: String, number: Int) {
        self.id = id
        self.name = name
        self.number = number
    }
}

/// One team's players. Team sheets are optional — a match with no squads is
/// still fully recordable, by shirt number alone.
public struct Squad: Codable, Sendable, Equatable, Identifiable {
    public var team: Team
    public var players: [Player]

    /// The team's id is the squad's id — one identity, not two.
    public var id: UUID { team.id }

    public init(team: Team, players: [Player] = []) {
        self.team = team
        self.players = players
    }
}

/// A match as the phone sets it up and sends to the watch.
public struct MatchSetup: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var home: Team
    public var away: Team
    public var competition: String?
    public var kickOff: Date?
    public var clock: ClockConfig
    /// Team sheets when the referee has them; empty is fine.
    public var squads: [Squad]
    /// How long a sin bin lasts in this match. It rides with the setup
    /// because the watch cannot read the phone's settings — the two devices
    /// have separate `UserDefaults`.
    public var sinBinMinutes: Int
    /// The preset this match was set up from (`MatchFormat.id`), if any —
    /// the report names the division and the watch can show its reminders.
    /// Optional, so a setup saved before formats existed still decodes.
    public var formatID: String?
    /// How long the break runs — the watch buzzes when it is over.
    public var halfTimeMinutes: Int
    /// Whether the watch offers "+1 min" for announced added time. Off unless
    /// asked for (Kevin, 2026-10-04): youth matches rarely announce any, and
    /// the clock shows the overrun either way.
    public var addedTimeButton: Bool
    /// A break partway through each half, with the clock stopped — nil when
    /// the match has none.
    public var quarterBreak: QuarterBreak?

    public init(id: UUID = UUID(), home: Team, away: Team, competition: String? = nil,
                kickOff: Date? = nil, clock: ClockConfig = .adult, squads: [Squad] = [],
                sinBinMinutes: Int = MatchDefaults.standard.sinBinMinutes,
                formatID: String? = nil,
                halfTimeMinutes: Int = MatchDefaults.standard.halfTimeMinutes,
                addedTimeButton: Bool = MatchDefaults.standard.addedTimeButton,
                quarterBreak: QuarterBreak? = nil) {
        self.id = id
        self.home = home
        self.away = away
        self.competition = competition
        self.kickOff = kickOff
        self.clock = clock
        self.squads = squads
        self.sinBinMinutes = sinBinMinutes
        self.formatID = formatID
        self.halfTimeMinutes = halfTimeMinutes
        self.addedTimeButton = addedTimeButton
        self.quarterBreak = quarterBreak
    }

    private enum CodingKeys: String, CodingKey {
        case id, home, away, competition, kickOff, clock, squads, sinBinMinutes, formatID, halfTimeMinutes
        case addedTimeButton, quarterBreak
    }

    /// ! Written out for one reason: a setup saved by build 22 or 25 has no
    /// `halfTimeMinutes`, and a synthesized decoder would refuse the whole
    /// match over it. Missing means the default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        home = try c.decode(Team.self, forKey: .home)
        away = try c.decode(Team.self, forKey: .away)
        competition = try c.decodeIfPresent(String.self, forKey: .competition)
        kickOff = try c.decodeIfPresent(Date.self, forKey: .kickOff)
        clock = try c.decode(ClockConfig.self, forKey: .clock)
        squads = try c.decode([Squad].self, forKey: .squads)
        sinBinMinutes = try c.decodeIfPresent(Int.self, forKey: .sinBinMinutes)
            ?? MatchDefaults.standard.sinBinMinutes
        formatID = try c.decodeIfPresent(String.self, forKey: .formatID)
        halfTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .halfTimeMinutes)
            ?? MatchDefaults.standard.halfTimeMinutes
        addedTimeButton = try c.decodeIfPresent(Bool.self, forKey: .addedTimeButton) ?? false
        quarterBreak = try c.decodeIfPresent(QuarterBreak.self, forKey: .quarterBreak)
    }

    public var format: MatchFormat? { MatchFormat.preset(id: formatID) }

    /// The field size to draw: the division's, or full size.
    public var pitchSize: PitchSize { format?.pitch ?? .adult }

    public func team(_ side: TeamSide) -> Team { side == .home ? home : away }

    public func squad(for side: TeamSide) -> Squad? {
        let wanted = team(side).id
        return squads.first { $0.team.id == wanted }
    }
}

/// The referee's defaults, set on the phone: what a new match starts from,
/// and what the watch's quick start uses. Sent with every assignment, because
/// the watch cannot read the phone's settings.
public struct MatchDefaults: Codable, Sendable, Equatable {
    public var halfMinutes: Int
    public var sinBinMinutes: Int
    public var halfTimeMinutes: Int
    public var addedTimeButton: Bool
    /// Quarter breaks for a quick start, nil for none.
    public var quarterBreak: QuarterBreak?

    public init(halfMinutes: Int = 45, sinBinMinutes: Int = 10, halfTimeMinutes: Int = 5,
                addedTimeButton: Bool = false, quarterBreak: QuarterBreak? = nil) {
        self.halfMinutes = halfMinutes
        self.sinBinMinutes = sinBinMinutes
        self.halfTimeMinutes = halfTimeMinutes
        self.addedTimeButton = addedTimeButton
        self.quarterBreak = quarterBreak
    }

    private enum CodingKeys: String, CodingKey {
        case halfMinutes, sinBinMinutes, halfTimeMinutes, addedTimeButton, quarterBreak
    }

    /// Missing `halfTimeMinutes` (an assignment the watch saved from build 22
    /// or 25) means the default, not a refusal.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        halfMinutes = try c.decode(Int.self, forKey: .halfMinutes)
        sinBinMinutes = try c.decode(Int.self, forKey: .sinBinMinutes)
        halfTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .halfTimeMinutes) ?? 5
        addedTimeButton = try c.decodeIfPresent(Bool.self, forKey: .addedTimeButton) ?? false
        quarterBreak = try c.decodeIfPresent(QuarterBreak.self, forKey: .quarterBreak)
    }

    /// The adult game: 45-minute halves, a five-minute break.
    public static let standard = MatchDefaults()
}

extension Team {
    /// A team to be named later — what a quick match starts with, on the
    /// phone and on the watch alike. Blue at home, red away, so the two are
    /// told apart before anyone edits them.
    public static func placeholder(_ side: TeamSide) -> Team {
        side == .home
            ? Team(name: "Home", abbreviation: "HOM", color: .blue)
            : Team(name: "Away", abbreviation: "AWY", color: .red)
    }
}

extension MatchSetup {
    /// Home and away the other way round. The squads follow their teams by
    /// id, so a team sheet stays with its team.
    public func swappingSides() -> MatchSetup {
        var swapped = self
        (swapped.home, swapped.away) = (away, home)
        return swapped
    }
}

/// A quarter break: the clock stops partway through each half for a drink
/// and substitutions, then starts again (Kevin, 2026-10-04).
public struct QuarterBreak: Codable, Sendable, Equatable {
    /// Minutes into each half when the break is due; nil means midway, so it
    /// follows the half length when that changes.
    public var atMinute: Int?
    /// How long the break runs before the watch buzzes.
    public var breakMinutes: Int

    public init(atMinute: Int? = nil, breakMinutes: Int = 2) {
        self.atMinute = atMinute
        self.breakMinutes = breakMinutes
    }

    /// Seconds into a half when the break is due.
    public func mark(halfLength: TimeInterval) -> TimeInterval {
        if let atMinute { return TimeInterval(atMinute * 60) }
        return (halfLength / 2 / 60).rounded(.down) * 60
    }
}
