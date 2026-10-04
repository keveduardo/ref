import Foundation
@testable import RefKit

/// Shared fixtures. Times are offsets from a fixed epoch, so nothing in the
/// suite depends on when it runs.
enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Whole seconds only, on purpose: `45 * 60` in a tuple literal is an Int
    /// to Swift 6.0's type-checker and a TimeInterval to 6.4's, and the kit
    /// must build on the oldest toolchain it claims.
    static func at(_ seconds: Int) -> Date { t0.addingTimeInterval(TimeInterval(seconds)) }

    static let home = Team(name: "Real Madrid Club", abbreviation: "RMC", color: .white)
    static let away = Team(name: "Arsenal", abbreviation: "ARS", color: .red)

    static let home9 = Player(name: "Striker", number: 9)
    static let home4 = Player(name: "Centre back", number: 4)
    static let away7 = Player(name: "Winger", number: 7)
    static let away11 = Player(name: "Forward", number: 11)

    static var setup: MatchSetup {
        MatchSetup(home: home, away: away, competition: "Friendly", clock: .adult,
                   squads: [Squad(team: home, players: [home9, home4]),
                            Squad(team: away, players: [away7, away11])])
    }

    static func event(_ seconds: Int, _ kind: MatchEvent.Kind) -> MatchEvent {
        MatchEvent(at: at(seconds), kind: kind)
    }

    /// A full friendly: 1–1, a yellow, an own goal and a red, with two minutes
    /// announced in the first half. Half 1 runs 0–45+2:10; the second 60–105.
    static func playedMatch() -> Match {
        let events: [MatchEvent] = [
            event(0, .kickOff(half: 1)),
            // 11:30 — the 12th minute, as a referee writes it.
            event(11 * 60 + 30, .goal(side: .home, scorer: PlayerRef(home9))),
            event(34 * 60, .yellowCard(side: .away, player: PlayerRef(away7))),
            event(45 * 60, .addedTime(half: 1, seconds: 120)),
            event(45 * 60 + 130, .goal(side: .away, scorer: PlayerRef(away11))),
            event(45 * 60 + 130, .halfEnd(half: 1)),
            event(60 * 60, .kickOff(half: 2)),
            event(60 * 60 + 600, .redCard(side: .home, player: PlayerRef(home4))),
            event(105 * 60, .fullTime),
        ]
        return Match(setup: setup, events: EventLog(events: events),
                     metrics: MatchMetrics(distanceMeters: 8_540, averageHeartRate: 132,
                                           maxHeartRate: 178, activeCalories: 720,
                                           workoutUUID: "0000-1111"),
                     createdAt: at(0))
    }
}
