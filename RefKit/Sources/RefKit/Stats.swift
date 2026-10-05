import Foundation

/// The season, folded from the finished matches — the phone's Stats screen.
public struct SeasonStats: Codable, Sendable, Equatable {
    public var matches: Int
    public var goals: Int
    public var yellowCards: Int
    public var redCards: Int
    public var sinBins: Int
    /// The referee's own season, from each match's frozen metrics. Each
    /// counts only the matches that recorded it, so a match played without
    /// Health access does not drag an average down.
    public var activity = Activity()

    public struct Activity: Codable, Sendable, Equatable {
        public var distanceMeters = 0.0
        public var matchesWithDistance = 0
        public var steps = 0
        public var matchesWithSteps = 0
        /// Sum of each match's average heart rate, for the season's mean.
        public var heartRateSum = 0.0
        public var matchesWithHeartRate = 0
        public var maxHeartRate: Double?
        public var activeCalories = 0.0

        public init() {}

        public var distancePerMatch: Double? {
            matchesWithDistance == 0 ? nil : distanceMeters / Double(matchesWithDistance)
        }
        public var stepsPerMatch: Int? {
            matchesWithSteps == 0 ? nil : steps / matchesWithSteps
        }
        public var averageHeartRate: Double? {
            matchesWithHeartRate == 0 ? nil : heartRateSum / Double(matchesWithHeartRate)
        }
        /// Whether any match has recorded anything at all.
        public var isEmpty: Bool {
            matchesWithDistance == 0 && matchesWithSteps == 0 && matchesWithHeartRate == 0 && activeCalories == 0
        }
    }

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
            if let m = match.metrics {
                if let d = m.distanceMeters, d > 0 {
                    stats.activity.distanceMeters += d
                    stats.activity.matchesWithDistance += 1
                }
                if let s = m.steps, s > 0 {
                    stats.activity.steps += s
                    stats.activity.matchesWithSteps += 1
                }
                if let hr = m.averageHeartRate, hr > 0 {
                    stats.activity.heartRateSum += hr
                    stats.activity.matchesWithHeartRate += 1
                }
                if let peak = m.maxHeartRate, peak > 0 {
                    stats.activity.maxHeartRate = max(stats.activity.maxHeartRate ?? 0, peak)
                }
                stats.activity.activeCalories += m.activeCalories ?? 0
            }
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
