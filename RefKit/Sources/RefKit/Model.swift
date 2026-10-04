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

    public init(id: UUID = UUID(), home: Team, away: Team, competition: String? = nil,
                kickOff: Date? = nil, clock: ClockConfig = .adult, squads: [Squad] = [],
                sinBinMinutes: Int = MatchDefaults.standard.sinBinMinutes,
                formatID: String? = nil) {
        self.id = id
        self.home = home
        self.away = away
        self.competition = competition
        self.kickOff = kickOff
        self.clock = clock
        self.squads = squads
        self.sinBinMinutes = sinBinMinutes
        self.formatID = formatID
    }

    public var format: MatchFormat? { MatchFormat.preset(id: formatID) }

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

    public init(halfMinutes: Int = 45, sinBinMinutes: Int = 10) {
        self.halfMinutes = halfMinutes
        self.sinBinMinutes = sinBinMinutes
    }

    /// The adult game: 45-minute halves, ten-minute sin bins.
    public static let standard = MatchDefaults()
}
