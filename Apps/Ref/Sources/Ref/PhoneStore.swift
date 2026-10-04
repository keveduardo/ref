import Foundation
import Observation
import RefKit

/// The phone's model: the teams, the shelf of matches, and the one on the
/// watch. Everything is a file in the app's own container; nothing here talks
/// to a server, and nothing needs one.
/// Where routes live on the phone, one JSON file per match. Not on the
/// main actor: `PhoneLink` files a route from inside the WatchConnectivity
/// callback, before the system deletes the transferred file.
enum RouteFiles {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return base.appendingPathComponent("Ref/routes", isDirectory: true)
    }

    static func url(for matchID: UUID, in directory: URL = directory) -> URL {
        directory.appendingPathComponent("\(matchID.uuidString).json")
    }

    /// Files a received route by its match id. Returns false when the file is
    /// not a route this build can read.
    @discardableResult
    static func file(_ data: Data, in directory: URL = directory) -> Bool {
        guard let route = try? SyncPayload.decode(SyncPayload.Route.self, from: data) else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try? data.write(to: url(for: route.matchID, in: directory), options: .atomic)) != nil
    }
}

@MainActor @Observable final class PhoneStore {
    private let matches: MatchStore
    private let library: TeamLibrary
    private let routesDirectory: URL
    /// Bumped when a route arrives, so a screen showing that match redraws.
    private(set) var routesVersion = 0

    /// Every match on the shelf — upcoming and played alike; `isFinished`
    /// tells them apart.
    private(set) var all: [Match] = []
    private(set) var squads: [Squad] = []

    init(matches: MatchStore = MatchStore(directory: PhoneStore.directory),
         library: TeamLibrary = TeamLibrary(directory: PhoneStore.directory),
         routesDirectory: URL = RouteFiles.directory) {
        self.matches = matches
        self.library = library
        self.routesDirectory = routesDirectory
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

    // MARK: - Routes

    /// The route the watch recorded for a match, if it has arrived.
    func route(for matchID: UUID) -> [RoutePoint]? {
        _ = routesVersion
        guard let data = try? Data(contentsOf: RouteFiles.url(for: matchID, in: routesDirectory)) else {
            return nil
        }
        return try? SyncPayload.decode(SyncPayload.Route.self, from: data).points
    }

    func routesChanged() { routesVersion += 1 }

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
                     clock: ClockConfig,
                     halfTimeMinutes: Int = MatchDefaults.standard.halfTimeMinutes,
                     addedTimeButton: Bool = false,
                     formatID: String? = nil,
                     quarterBreak: QuarterBreak? = nil) -> Match {
        // Team sheets ride along when both teams are known — the watch offers
        // their numbers instead of 1–18.
        let sheets = [home, away].compactMap { squad(for: $0) }
        let setup = MatchSetup(home: home, away: away, competition: competition,
                               kickOff: kickOff, clock: clock, squads: sheets,
                               formatID: formatID, halfTimeMinutes: halfTimeMinutes,
                               addedTimeButton: addedTimeButton, quarterBreak: quarterBreak)
        let match = Match(setup: setup)
        try? matches.save(match)
        reload()
        return match
    }

    /// Games read from a scheduler's reminder email, onto the shelf. A game
    /// already here (same scheduler id) is left as it is — the referee may
    /// have edited it — so pasting the same reminder twice changes nothing.
    /// Returns how many were new.
    @discardableResult
    func importGames(from text: String) -> (new: Int, found: Int) {
        let games = ScheduledGame.parse(text)
        let defaults = UserDefaults.standard.integer(forKey: "ref.halfTimeMinutes")
        var new = 0
        for game in games {
            var setup = game.matchSetup(halfTimeMinutes: defaults == 0
                                        ? MatchDefaults.standard.halfTimeMinutes : defaults)
            setup.addedTimeButton = UserDefaults.standard.bool(forKey: "ref.addedTimeButton")
            // The division decides quarter breaks; without one, Settings does.
            if setup.format == nil {
                setup.quarterBreak = QuarterBreakDefaults.value
            } else if setup.quarterBreak != nil {
                setup.quarterBreak?.breakMinutes = QuarterBreakDefaults.breakMinutes
            }
            guard !all.contains(where: { $0.id == setup.id }) else { continue }
            try? matches.save(Match(setup: setup))
            new += 1
        }
        reload()
        return (new, games.count)
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
                               library: TeamLibrary(directory: dir),
                               routesDirectory: dir.appendingPathComponent("routes"))

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
                                      maxHeartRate: 181, activeCalories: 812, steps: 11_406)
        let field = PitchFrame(latitude: 33.85, longitude: -118.38, bearing: 30, marked: true)
        played.pitch = field
        store.save(played)
        // A plausible diagonal: corner to corner with the play, drifting.
        let kick = at(2 * 86_400 + 40 * 60)
        var points: [RoutePoint] = []
        for i in 0..<2_700 {
            let t = Double(i) * 2
            let along = sin(t / 140) * 0.8 + sin(t / 37) * 0.15
            let x = along * 42, y = along * 22 + sin(t / 23) * 6
            points.append(field.point(x: x, y: y, at: kick.addingTimeInterval(t)))
        }
        RouteFiles.file((try? SyncPayload.encode(SyncPayload.Route(matchID: played.id, points: points))) ?? Data(),
                        in: dir.appendingPathComponent("routes"))

        store.createMatch(home: away, away: home, competition: "League — Saturday",
                          kickOff: now.addingTimeInterval(2 * 86_400), clock: .adult)
        return store
    }
}
#endif
