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
    /// The league's team number ("A1 02") and the coach, for the report and
    /// the check-in (Kevin, 2026-11-06). Optional, so a team saved before
    /// them still decodes.
    public var number: String?
    public var coach: String?

    public init(id: UUID = UUID(), name: String, abbreviation: String? = nil,
                color: TeamColor = .blue, number: String? = nil, coach: String? = nil) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation ?? Team.defaultAbbreviation(name)
        self.color = color
        self.number = number
        self.coach = coach
    }

    /// "Team A1 02 · Coach Smith", or nil with neither.
    public var details: String? {
        let parts = [number.map { "Team \($0)" }, coach.map { "Coach \($0)" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "Team" && $0 != "Coach" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

/// The referee's own slot in a match (Kevin, 2026-11-12: "on the cards can
/// it actually show my assignment? CR or AR?"). "AR" when the scheduler does
/// not say which assistant.
public enum RefereeRole: String, Codable, Sendable, Equatable, CaseIterable {
    case cr = "CR", ar = "AR", ar1 = "AR1", ar2 = "AR2", fourth = "4th"

    /// The schedule's own word for a slot: "Center", "AR", "AR2", "4th".
    public init?(scheduled position: String) {
        switch position.trimmingCharacters(in: .whitespaces).uppercased() {
        case "CENTER", "CENTRE", "CR", "REFEREE": self = .cr
        case "AR", "ASSISTANT", "ASSISTANT REFEREE": self = .ar
        case "AR1": self = .ar1
        case "AR2": self = .ar2
        case "4TH", "4TH OFFICIAL", "FOURTH": self = .fourth
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .cr: "Center referee"
        case .ar: "Assistant referee"
        case .ar1: "Assistant referee 1"
        case .ar2: "Assistant referee 2"
        case .fourth: "Fourth official"
        }
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
    /// A break partway through each half — nil when the match has none.
    public var quarterBreak: QuarterBreak?
    /// The referees' names, for the report — nil when not given. The centre
    /// referee joined the assistants on 2026-11-06 (Kevin: "needs a center
    /// ref option as well").
    public var cr: String?
    public var ar1: String?
    public var ar2: String?
    /// Which slot is the referee's own — nil when not known.
    public var myRole: RefereeRole?

    public init(id: UUID = UUID(), home: Team, away: Team, competition: String? = nil,
                kickOff: Date? = nil, clock: ClockConfig = .adult, squads: [Squad] = [],
                sinBinMinutes: Int = MatchDefaults.standard.sinBinMinutes,
                formatID: String? = nil,
                halfTimeMinutes: Int = MatchDefaults.standard.halfTimeMinutes,
                addedTimeButton: Bool = MatchDefaults.standard.addedTimeButton,
                quarterBreak: QuarterBreak? = nil,
                cr: String? = nil, ar1: String? = nil, ar2: String? = nil,
                myRole: RefereeRole? = nil) {
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
        self.cr = cr
        self.ar1 = ar1
        self.ar2 = ar2
        self.myRole = myRole
    }

    private enum CodingKeys: String, CodingKey {
        case id, home, away, competition, kickOff, clock, squads, sinBinMinutes, formatID, halfTimeMinutes
        case addedTimeButton, quarterBreak, cr, ar1, ar2, myRole
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
        cr = try c.decodeIfPresent(String.self, forKey: .cr)
        ar1 = try c.decodeIfPresent(String.self, forKey: .ar1)
        ar2 = try c.decodeIfPresent(String.self, forKey: .ar2)
        // An older watch or phone that knows no role, or a role this build
        // does not know, is simply no role — never a refused match.
        myRole = (try? c.decodeIfPresent(RefereeRole.self, forKey: .myRole)) ?? nil
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

/// A quarter break partway through each half, for a drink and substitutions.
/// The match clock keeps running through it — the half is a running clock
/// (Kevin, 2026-10-04); the break has its own timer and buzz.
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

extension MatchSetup {
    /// The phone's edits to a match the watch is already running. Names,
    /// short names, colours, home and away, competition and team sheets always
    /// come across — they change nothing about the match's record. The clock
    /// (half length, count-down, half-time, quarter breaks, added-time button)
    /// only before kick-off: changing it mid-half would rewrite the minutes of
    /// everything already recorded.
    public func applyingEdits(_ edited: MatchSetup, kickedOff: Bool) -> MatchSetup {
        guard edited.id == id else { return self }
        var merged = self
        merged.home = edited.home
        merged.away = edited.away
        merged.competition = edited.competition
        merged.squads = edited.squads
        merged.kickOff = edited.kickOff
        merged.cr = edited.cr
        merged.ar1 = edited.ar1
        merged.ar2 = edited.ar2
        merged.myRole = edited.myRole
        if !kickedOff {
            merged.clock = edited.clock
            merged.halfTimeMinutes = edited.halfTimeMinutes
            merged.quarterBreak = edited.quarterBreak
            merged.addedTimeButton = edited.addedTimeButton
            merged.formatID = edited.formatID
        }
        return merged
    }
}

extension MatchSetup {
    public mutating func setColor(_ color: TeamColor, for side: TeamSide) {
        if side == .home { home.color = color } else { away.color = color }
    }

    /// The phone's edits, with the colours just chosen on the watch held
    /// (Kevin, 2026-11-12: team colours from the watch, mid-match). The
    /// phone's copy is the one that gets edited, and it only hears of the
    /// watch's choice a moment later, so a list it sent in between would undo
    /// it. A held colour stays until the phone's copy has it too; then it is
    /// let go, and the phone may change it again.
    public func applyingEdits(_ edited: MatchSetup, kickedOff: Bool,
                              holding held: inout [TeamSide: TeamColor]) -> MatchSetup {
        var merged = applyingEdits(edited, kickedOff: kickedOff)
        guard edited.id == id else { return merged }
        for (side, color) in held {
            if edited.team(side).color == color {
                held[side] = nil
            } else {
                merged.setColor(color, for: side)
            }
        }
        return merged
    }
}
