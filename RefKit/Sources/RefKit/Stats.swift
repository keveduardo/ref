import Foundation

/// The season, folded from the finished matches — the phone's Stats screen.
public struct SeasonStats: Codable, Sendable, Equatable {
    public var matches: Int
    public var goals: Int
    public var yellowCards: Int
    public var redCards: Int
    public var sinBins: Int

    public init(matches: Int = 0, goals: Int = 0, yellowCards: Int = 0,
                redCards: Int = 0, sinBins: Int = 0) {
        self.matches = matches
        self.goals = goals
        self.yellowCards = yellowCards
        self.redCards = redCards
        self.sinBins = sinBins
    }

    public static func make(from matches: [Match]) -> SeasonStats {
        var stats = SeasonStats()
        for match in matches {
            let report = match.report
            stats.matches += 1
            stats.goals += report.totals.homeGoals + report.totals.awayGoals
            stats.yellowCards += report.totals.yellowCards
            stats.redCards += report.totals.redCards
            stats.sinBins += report.totals.sinBins
        }
        return stats
    }

    /// Cards of both colours, per match — one decimal place is enough for a
    /// referee's season.
    public var cardsPerMatch: Double {
        matches == 0 ? 0 : Double(yellowCards + redCards) / Double(matches)
    }

    public var totalCards: Int { yellowCards + redCards }
}
