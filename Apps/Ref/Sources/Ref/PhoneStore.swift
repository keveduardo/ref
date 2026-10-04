import Foundation
import Observation
import RefKit

/// The phone's model: the teams, the shelf of matches, and the one on the
/// watch. Everything is a file in the app's own container; nothing here talks
/// to a server, and nothing needs one.
@MainActor @Observable final class PhoneStore {
    private let matches: MatchStore
    private let library: TeamLibrary

    /// Every match on the shelf — upcoming and played alike; `isFinished`
    /// tells them apart.
    private(set) var all: [Match] = []
    private(set) var squads: [Squad] = []

    init(matches: MatchStore = MatchStore(directory: PhoneStore.directory),
         library: TeamLibrary = TeamLibrary(directory: PhoneStore.directory)) {
        self.matches = matches
        self.library = library
        reload()
    }

    static var directory: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return base.appendingPathComponent("Ref", isDirectory: true)
    }

    func reload() {
        all = (try? matches.all()) ?? []
        squads = (try? library.all()) ?? []
    }

    var upcoming: [Match] {
        all.filter { !$0.isFinished }
            .sorted { ($0.setup.kickOff ?? $0.createdAt) < ($1.setup.kickOff ?? $1.createdAt) }
    }

    var played: [Match] { all.filter(\.isFinished) }

    var stats: SeasonStats { SeasonStats.make(from: played) }

    // MARK: - Teams

    func saveTeam(_ squad: Squad) {
        try? library.save(squad)
        reload()
    }

    func deleteTeam(_ squad: Squad) {
        try? library.delete(teamID: squad.team.id)
        reload()
    }

    func squad(for team: Team) -> Squad? {
        squads.first { $0.team.id == team.id }
    }

    // MARK: - Matches

    @discardableResult
    func createMatch(home: Team, away: Team, competition: String?, kickOff: Date?,
                     clock: ClockConfig) -> Match {
        // Team sheets ride along when both teams are known — the watch offers
        // their numbers instead of 1–18.
        let sheets = [home, away].compactMap { squad(for: $0) }
        let setup = MatchSetup(home: home, away: away, competition: competition,
                               kickOff: kickOff, clock: clock, squads: sheets)
        let match = Match(setup: setup)
        try? matches.save(match)
        reload()
        return match
    }

    func save(_ match: Match) {
        try? matches.save(match)
        reload()
    }

    func delete(_ match: Match) {
        try? matches.delete(id: match.id)
        reload()
    }
}

#if DEBUG
extension PhoneStore {
    /// Seeded with a plausible season, in a throwaway container — for the
    /// `render` job's screenshots. Never touches the real one.
    static func demo() -> PhoneStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ref-phone-render-\(UUID().uuidString)", isDirectory: true)
        let store = PhoneStore(matches: MatchStore(directory: dir),
                               library: TeamLibrary(directory: dir))

        let home = Team(name: "Real Madrid Club", abbreviation: "RMC", color: .white)
        let away = Team(name: "Arsenal", abbreviation: "ARS", color: .red)
        store.saveTeam(Squad(team: home, players: [
            Player(name: "Courtois", number: 1), Player(name: "Carvajal", number: 2),
            Player(name: "Militão", number: 3), Player(name: "Vinícius", number: 7),
            Player(name: "Bellingham", number: 5), Player(name: "Mbappé", number: 9),
        ]))
        store.saveTeam(Squad(team: away, players: [
            Player(name: "Raya", number: 22), Player(name: "Saka", number: 7),
            Player(name: "Ødegaard", number: 8), Player(name: "Havertz", number: 29),
        ]))

        let now = Date()
        /// Whole seconds, so an older type-checker cannot read the arithmetic
        /// as an Int (the Swift 6.0 trap from the kit's tests).
        func at(_ secondsAgo: Int) -> Date {
            now.addingTimeInterval(TimeInterval(-secondsAgo))
        }

        var played = Match(setup: MatchSetup(
            home: home, away: away, competition: "Friendly",
            kickOff: at(2 * 86_400),
            squads: store.squads), createdAt: at(2 * 86_400))
        played.events = EventLog(events: [
            MatchEvent(at: at(2 * 86_400 + 40 * 60), kind: .kickOff(half: 1)),
            MatchEvent(at: at(2 * 86_400 + 28 * 60), kind: .goal(side: .home, scorer: PlayerRef(number: 9))),
            MatchEvent(at: at(2 * 86_400 + 10 * 60), kind: .yellowCard(side: .away, player: PlayerRef(number: 8))),
            MatchEvent(at: at(2 * 86_400 + 2 * 60), kind: .addedTime(half: 1, seconds: 120)),
            MatchEvent(at: at(2 * 86_400 + 2 * 60), kind: .halfEnd(half: 1)),
            MatchEvent(at: at(1 * 86_400 + 50 * 60), kind: .kickOff(half: 2)),
            MatchEvent(at: at(1 * 86_400 + 20 * 60), kind: .goal(side: .away, scorer: PlayerRef(number: 7))),
            MatchEvent(at: at(1 * 86_400), kind: .fullTime),
        ])
        played.metrics = MatchMetrics(distanceMeters: 9_120, averageHeartRate: 134,
                                      maxHeartRate: 181, activeCalories: 812)
        store.save(played)

        store.createMatch(home: away, away: home, competition: "League — Saturday",
                          kickOff: now.addingTimeInterval(2 * 86_400), clock: .adult)
        return store
    }
}
#endif
