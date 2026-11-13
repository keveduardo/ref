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
    /// Told of every change made on this phone — the account backs it up.
    /// Changes that arrive from the backup (`applyFromSync`) do not call it.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored var onDelete: (@MainActor (String, UUID) -> Void)?

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

    /// Matches the watch took on itself (a quick start, usually), until they
    /// come back finished. Kept apart from Upcoming, because on the watch
    /// they are not waiting to be picked — they are the match in hand.
    var onWatch: [Match] {
        all.filter { !$0.isFinished && startedOnWatch.contains($0.id) }
    }

    /// Which matches the watch has, and which of them it made (RefKit's
    /// `WatchHandoff`), remembered across launches.
    private var handoff = WatchHandoff(
        onWatch: Self.ids("ref.startedOnWatch"), madeOnWatch: Self.ids("ref.madeOnWatch")) {
        didSet {
            UserDefaults.standard.set(handoff.onWatch.map(\.uuidString), forKey: "ref.startedOnWatch")
            UserDefaults.standard.set(handoff.madeOnWatch.map(\.uuidString), forKey: "ref.madeOnWatch")
        }
    }

    var startedOnWatch: Set<UUID> { handoff.onWatch }

    private static func ids(_ key: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init))
    }

    /// Not yet played, and not a day past kick-off unstarted — those are
    /// `notRefereed` (RefKit's `Match.isRetired`). This is also the watch's list.
    var upcoming: [Match] {
        all.filter { !$0.isFinished && !startedOnWatch.contains($0.id) && !$0.isRetired() }
            .sorted { ($0.setup.kickOff ?? $0.createdAt) < ($1.setup.kickOff ?? $1.createdAt) }
    }

    /// Scheduled games nobody started, a day past kick-off, newest first.
    var notRefereed: [Match] {
        all.filter { !startedOnWatch.contains($0.id) && $0.isRetired() }
            .sorted { ($0.setup.kickOff ?? $0.createdAt) > ($1.setup.kickOff ?? $1.createdAt) }
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
        onChange?()
    }

    func deleteTeam(_ squad: Squad) {
        try? library.delete(teamID: squad.team.id)
        reload()
        onDelete?("team", squad.id)
        onChange?()
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
                     quarterBreak: QuarterBreak? = nil,
                     cr: String? = nil, ar1: String? = nil, ar2: String? = nil) -> Match {
        // Team sheets ride along when both teams are known — the watch offers
        // their numbers instead of 1–18.
        let sheets = [home, away].compactMap { squad(for: $0) }
        let setup = MatchSetup(home: home, away: away, competition: competition,
                               kickOff: kickOff, clock: clock, squads: sheets,
                               formatID: formatID, halfTimeMinutes: halfTimeMinutes,
                               addedTimeButton: addedTimeButton, quarterBreak: quarterBreak,
                               cr: cr, ar1: ar1, ar2: ar2)
        let match = Match(setup: setup)
        try? matches.save(match)
        reload()
        onChange?()
        return match
    }

    /// Games onto the shelf. A game already here (same scheduler id) is
    /// left as it is — the referee may have edited it. With `followSite`
    /// (the CGI schedule, read again every hour), a match not yet played and
    /// not yet on the watch takes the site's kick-off and crew when they
    /// change — the assignor moves games and swaps referees. Returns new and
    /// updated.
    @discardableResult
    func importGames(_ games: [ScheduledGame], followSite: Bool = false) -> (new: Int, updated: Int) {
        let defaults = UserDefaults.standard.integer(forKey: "ref.halfTimeMinutes")
        var new = 0
        var updated = 0
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
            if var existing = all.first(where: { $0.id == setup.id }) {
                guard followSite, !existing.isFinished, !startedOnWatch.contains(existing.id) else { continue }
                var changed = existing.setup
                changed.kickOff = setup.kickOff
                // The site's crew as it stands — an open slot clears a name,
                // which also undoes a crew misread before 2026-11-12.
                // Only when the game's page was read — a page that timed out
                // says nothing about the crew.
                if game.crewKnown {
                    changed.cr = setup.cr
                    changed.ar1 = setup.ar1
                    changed.ar2 = setup.ar2
                }
                changed.myRole = setup.myRole ?? changed.myRole
                guard changed != existing.setup else { continue }
                existing.setup = changed
                try? matches.save(existing)
                updated += 1
                continue
            }
            try? matches.save(Match(setup: setup))
            new += 1
        }
        reload()
        if new > 0 || updated > 0 { onChange?() }
        return (new, updated)
    }

    func save(_ match: Match) {
        try? matches.save(match)
        reload()
        onChange?()
    }

    /// A finished match from the watch. Merged into the phone's copy when
    /// there is one, so names given here after full time, and a goal added
    /// on either side, are kept (`Match.receivingFromWatch`).
    func finishedOnWatch(_ incoming: Match) {
        let merged = all.first(where: { $0.id == incoming.id })
            .map { $0.receivingFromWatch(incoming) } ?? incoming
        if merged.isFinished { handoff.forget(merged.id) }
        save(merged)
    }

    func delete(_ match: Match) {
        handoff.forget(match.id)
        try? matches.delete(id: match.id)
        reload()
        onDelete?("match", match.id)
        onChange?()
    }

    /// A match the watch took on (a quick start, usually): listed under
    /// Upcoming so it can be edited here. One already here is left alone —
    /// the phone's copy is where edits are made.
    func addStartedOnWatch(_ setup: MatchSetup) {
        let phoneHadIt = all.contains(where: { $0.id == setup.id })
        handoff.started(setup.id, phoneHadIt: phoneHadIt)
        guard !phoneHadIt else { reload(); return }
        save(Match(setup: setup))
    }

    /// Team colours chosen on the watch, mid-match too: taken into the
    /// phone's copy, which then goes back to the watch as usual. Only the
    /// colours — names and the rest are edited here.
    func colorsChangedOnWatch(_ setup: MatchSetup) {
        guard var match = all.first(where: { $0.id == setup.id }) else {
            addStartedOnWatch(setup)
            return
        }
        var changed = match.setup
        changed.setColor(setup.home.color, for: .home)
        changed.setColor(setup.away.color, for: .away)
        guard changed != match.setup else { return }
        match.setup = changed
        save(match)
    }

    /// The watch's report of its match in hand. Any other watch-started match
    /// it no longer has goes back to Upcoming — on the watch's list again,
    /// to be picked — rather than claiming to be on the watch.
    func watchIsRunning(_ id: UUID?) {
        guard startedOnWatch.contains(where: { $0 != id }) else { return }
        handoff.running(id)
        reload()
    }

    /// Put back on the watch before kick-off. A quick start was never more
    /// than a placeholder, so it goes; a match from the phone's list goes
    /// back to Upcoming, edits and all.
    func cancelledOnWatch(_ id: UUID) {
        let isQuickStart = handoff.cancelled(id)
        guard isQuickStart, let match = all.first(where: { $0.id == id }),
              !match.isFinished, match.events.recorded.isEmpty else { reload(); return }
        delete(match)
    }

    // MARK: - From the backup

    /// A match or team sheet that changed on another phone. A match keeps the
    /// health numbers and field this phone has for it — those never travel.
    func applyFromSync(kind: String, body: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(body.utf8)
        switch kind {
        case "match":
            guard var incoming = try? decoder.decode(Match.self, from: data) else { return }
            if let local = all.first(where: { $0.id == incoming.id }) {
                incoming.metrics = local.metrics
                incoming.pitch = local.pitch
            }
            try? matches.save(incoming)
        case "team":
            guard let squad = try? decoder.decode(Squad.self, from: data) else { return }
            try? library.save(squad)
        default:
            return
        }
        reload()
    }

    /// Deleted on another phone.
    func removeFromSync(kind: String, id: UUID) {
        switch kind {
        case "match": try? matches.delete(id: id)
        case "team": try? library.delete(teamID: id)
        default: return
        }
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

        // Invented teams and players — no real clubs or people (the repo's rule).
        let home = Team(name: "Harbor City FC", abbreviation: "HCF", color: .white)
        let away = Team(name: "Ridgeline United", abbreviation: "RLU", color: .red)
        store.saveTeam(Squad(team: home, players: [
            Player(name: "Player 1", number: 1), Player(name: "Player 2", number: 2),
            Player(name: "Player 3", number: 3), Player(name: "Player 7", number: 7),
            Player(name: "Player 5", number: 5), Player(name: "Player 9", number: 9),
        ]))
        store.saveTeam(Squad(team: away, players: [
            Player(name: "Player 22", number: 22), Player(name: "Player 7", number: 7),
            Player(name: "Player 8", number: 8), Player(name: "Player 29", number: 29),
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

        let upcoming = store.createMatch(home: away, away: home, competition: "League — Saturday",
                                         kickOff: now.addingTimeInterval(2 * 86_400), clock: .adult)
        var assigned = upcoming
        assigned.setup.myRole = .ar
        store.save(assigned)
        return store
    }
}
#endif
