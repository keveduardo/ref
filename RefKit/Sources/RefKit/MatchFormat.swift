import Foundation

/// A preset for a kind of match — the defaults a new match starts from when
/// the referee picks one. Every value is only a starting point: the phone
/// lets each of them be changed for the match in hand.
///
/// The AYSO presets follow **AYSO Region 34's Local Rules and Guidelines,
/// 2024 Fall Season** (Kevin's region), which take precedence over the
/// national rules where they differ — notably 10U plays 8 v 8 there, not
/// the national 7 v 7. What that sheet does not cover comes from the AYSO
/// National Rules & Regulations (01/2020), Article I: half-time of five to
/// ten minutes (B.2), heading banned in 12U and below for two-year
/// divisions (I.1), no punts in 10U and below (K.1). The rules are the same
/// for girls and boys; the division names both because the report should
/// say which it was.
public struct MatchFormat: Codable, Sendable, Equatable, Identifiable {
    public enum Gender: String, Codable, Sendable, Equatable, CaseIterable {
        case girls, boys

        public var title: String { self == .girls ? "Girls" : "Boys" }
    }

    /// Stable across releases — a saved match refers to its format by this.
    public var id: String
    /// "AYSO 12U Girls".
    public var title: String
    public var halfMinutes: Int
    /// Half-time, as the rules bound it; the referee designates within it.
    public var halfTimeMinutes: ClosedRange<Int>
    public var playersPerSide: Int
    /// Fewest players a team may start with.
    public var minimumPlayers: Int
    public var ballSize: Int
    public var goalkeepers: Bool
    /// Whether the score is kept. When not, the watch shows no score.
    public var keepsScore: Bool
    /// Every foul restarts with an indirect free kick (7U and 8U).
    public var allFoulsIndirect: Bool
    /// Whether a player may deliberately head the ball in a match. When not,
    /// a header is an indirect free kick.
    public var headingAllowed: Bool
    /// Whether the goalkeeper may punt or drop-kick.
    public var keeperMayPunt: Bool
    /// Whether the field has a build-out line.
    public var buildOutLine: Bool
    /// Where offside starts being called: "Halfway line", or nil when
    /// offside is not called at all.
    public var offsideLine: String?
    /// Substitutions at the quarters — the preset turns quarter breaks on.
    /// Otherwise free substitution.
    public var quarterSubstitutions: Bool
    /// Whether cards are shown. When not, the watch offers no cards.
    public var showsCards: Bool

    public init(id: String, title: String, halfMinutes: Int, halfTimeMinutes: ClosedRange<Int>,
                playersPerSide: Int, minimumPlayers: Int, ballSize: Int, goalkeepers: Bool,
                keepsScore: Bool, allFoulsIndirect: Bool, headingAllowed: Bool,
                keeperMayPunt: Bool, buildOutLine: Bool, offsideLine: String?,
                quarterSubstitutions: Bool, showsCards: Bool) {
        self.id = id
        self.title = title
        self.halfMinutes = halfMinutes
        self.halfTimeMinutes = halfTimeMinutes
        self.playersPerSide = playersPerSide
        self.minimumPlayers = minimumPlayers
        self.ballSize = ballSize
        self.goalkeepers = goalkeepers
        self.keepsScore = keepsScore
        self.allFoulsIndirect = allFoulsIndirect
        self.headingAllowed = headingAllowed
        self.keeperMayPunt = keeperMayPunt
        self.buildOutLine = buildOutLine
        self.offsideLine = offsideLine
        self.quarterSubstitutions = quarterSubstitutions
        self.showsCards = showsCards
    }

    /// The rules worth a glance before kick-off, one line — the phone's
    /// match-type footer.
    public var reminder: String {
        var bits = ["\(playersPerSide) v \(playersPerSide) (min \(minimumPlayers))", "size \(ballSize) ball"]
        if !goalkeepers { bits.append("no keepers") }
        if !keepsScore { bits.append("no score kept") }
        if allFoulsIndirect { bits.append("all fouls IFK") }
        if !headingAllowed { bits.append("no heading") }
        if goalkeepers && !keeperMayPunt { bits.append("no punts") }
        if buildOutLine { bits.append("build-out line") }
        bits.append(offsideLine.map { "offside from the \($0.lowercased())" } ?? "no offside")
        bits.append(quarterSubstitutions ? "subs at quarters" : "free subs")
        bits.append(showsCards ? "cards" : "no cards")
        bits.append("half-time \(halfTimeMinutes.lowerBound)–\(halfTimeMinutes.upperBound) min")
        return bits.joined(separator: " · ")
    }

    /// The short version for the watch before kick-off.
    public var watchReminder: String {
        var bits: [String] = []
        if !showsCards { bits.append("No cards") }
        if !headingAllowed { bits.append("no heading") }
        if allFoulsIndirect { bits.append("all IFK") }
        if offsideLine == nil { bits.append("no offside") }
        if buildOutLine { bits.append("build-out") }
        return bits.isEmpty ? "\(playersPerSide) v \(playersPerSide)" : bits.joined(separator: " · ")
    }

    // MARK: - The presets

    /// One row of Region 34's table, girls or boys.
    static func ayso(_ age: Int, _ gender: Gender) -> MatchFormat {
        // (half, players, min, ball, keepers, score, allIFK, buildOut, offside, qtrSubs, cards)
        let row: (Int, Int, Int, Int, Bool, Bool, Bool, Bool, String?, Bool, Bool)
        switch age {
        case 7:  row = (20, 7, 5, 3, false, false, true, true, nil, true, false)
        case 8:  row = (20, 7, 5, 3, true, false, true, true, nil, true, false)
        case 10: row = (25, 8, 6, 4, true, true, false, true, "Halfway line", true, false)
        case 12: row = (30, 9, 7, 4, true, true, false, false, "Halfway line", true, true)
        case 14: row = (35, 11, 7, 5, true, true, false, false, "Halfway line", true, true)
        case 16: row = (40, 11, 7, 5, true, true, false, false, "Halfway line", false, true)
        default: row = (45, 11, 7, 5, true, true, false, false, "Halfway line", false, true)
        }
        return MatchFormat(id: "ayso-\(age)u-\(gender.rawValue)",
                           title: "AYSO \(age)U \(gender.title)",
                           halfMinutes: row.0, halfTimeMinutes: 5...10,
                           playersPerSide: row.1, minimumPlayers: row.2, ballSize: row.3,
                           goalkeepers: row.4, keepsScore: row.5, allFoulsIndirect: row.6,
                           headingAllowed: age >= 14, keeperMayPunt: age > 10,
                           buildOutLine: row.7, offsideLine: row.8,
                           quarterSubstitutions: row.9, showsCards: row.10)
    }

    /// The divisions offered, youngest first — Region 34's table without 7U,
    /// which Kevin does not referee (2026-10-04). `ayso(7, _)` still knows
    /// the row, should it come back.
    public static let ages = [8, 10, 12, 14, 16, 19]

    /// What the phone's match-type picker offers, in its order.
    public static let presets: [MatchFormat] = ages.flatMap { age in
        Gender.allCases.map { ayso(age, $0) }
    }

    public static func preset(id: String?) -> MatchFormat? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    /// The division picked in two parts — the age from a short list, then
    /// girls or boys (Kevin, 2026-10-04: twelve names in one list was long).
    public static func preset(age: Int, gender: Gender) -> MatchFormat? {
        preset(id: "ayso-\(age)u-\(gender.rawValue)")
    }

    /// 8, 10, 12… — from the id, which carries it.
    public var age: Int {
        Int(id.split(separator: "-").dropFirst().first?.dropLast() ?? "") ?? 0
    }

    public var gender: Gender {
        id.hasSuffix(Gender.boys.rawValue) ? .boys : .girls
    }

    /// "AYSO 10U" — the name without girls or boys, for the age list.
    public static func ageTitle(_ age: Int) -> String { "AYSO \(age)U" }
}
