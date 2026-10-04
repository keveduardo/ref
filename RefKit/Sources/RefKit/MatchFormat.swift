import Foundation

/// A preset for a kind of match — the defaults a new match starts from when
/// the referee picks one. Every value is only a starting point: the phone
/// lets each of them be changed for the match in hand.
///
/// The AYSO values are from the AYSO National Rules & Regulations
/// (01/2020), Article I: B.1 (maximum duration of a half), B.2 (half-time
/// five to ten minutes), H.1 (team sizes), the ball-size table, I.1
/// (heading), K.1 (no punts in 9U–10U) and L (build-out line, 9U–10U). The
/// rules are the same for girls and boys; the division names both because
/// the match report should say which it was.
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
    public var ballSize: Int
    /// Whether a player may deliberately head the ball in a match. When not,
    /// a header is an indirect free kick.
    public var headingAllowed: Bool
    /// Whether the goalkeeper may punt or drop-kick.
    public var keeperMayPunt: Bool
    /// Whether the field has a build-out line (offside not called between it
    /// and the halfway line).
    public var buildOutLine: Bool

    public init(id: String, title: String, halfMinutes: Int, halfTimeMinutes: ClosedRange<Int>,
                playersPerSide: Int, ballSize: Int, headingAllowed: Bool,
                keeperMayPunt: Bool, buildOutLine: Bool) {
        self.id = id
        self.title = title
        self.halfMinutes = halfMinutes
        self.halfTimeMinutes = halfTimeMinutes
        self.playersPerSide = playersPerSide
        self.ballSize = ballSize
        self.headingAllowed = headingAllowed
        self.keeperMayPunt = keeperMayPunt
        self.buildOutLine = buildOutLine
    }

    /// The rules worth a glance before kick-off, one line:
    /// "7 a side · size 4 ball · no heading · no punts · build-out line".
    public var reminder: String {
        var bits = ["\(playersPerSide) a side", "size \(ballSize) ball"]
        if !headingAllowed { bits.append("no heading") }
        if !keeperMayPunt { bits.append("no punts") }
        if buildOutLine { bits.append("build-out line") }
        bits.append("half-time \(halfTimeMinutes.lowerBound)–\(halfTimeMinutes.upperBound) min")
        return bits.joined(separator: " · ")
    }

    // MARK: - The presets

    /// One AYSO division, girls or boys — the same rules either way.
    static func ayso(_ age: Int, _ gender: Gender) -> MatchFormat {
        let (half, players, ball, heading, punts, buildOut): (Int, Int, Int, Bool, Bool, Bool)
        switch age {
        case 10: (half, players, ball, heading, punts, buildOut) = (25, 7, 4, false, false, true)
        case 12: (half, players, ball, heading, punts, buildOut) = (30, 9, 4, false, true, false)
        default: (half, players, ball, heading, punts, buildOut) = (35, 11, 5, true, true, false)
        }
        return MatchFormat(id: "ayso-\(age)u-\(gender.rawValue)",
                           title: "AYSO \(age)U \(gender.title)",
                           halfMinutes: half, halfTimeMinutes: 5...10,
                           playersPerSide: players, ballSize: ball,
                           headingAllowed: heading, keeperMayPunt: punts,
                           buildOutLine: buildOut)
    }

    /// What the phone's match-type picker offers, in its order.
    public static let presets: [MatchFormat] = [10, 12, 14].flatMap { age in
        Gender.allCases.map { ayso(age, $0) }
    }

    public static func preset(id: String?) -> MatchFormat? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}
