import Foundation
import Testing
@testable import RefKit

@Suite("match store")
struct MatchStoreTests {
    /// A store in its own temp folder — nothing here touches a real container.
    func tempStore() -> MatchStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("refkit-tests-\(UUID().uuidString)", isDirectory: true)
        return MatchStore(directory: dir)
    }

    @Test func aMatchRoundTripsThroughJSONUnchanged() throws {
        let store = tempStore()
        let match = Fixture.playedMatch()
        try store.save(match)
        let back = try store.load(id: match.id)
        #expect(back == match)
        // And the clock rebuilt from the file reads exactly like the live one.
        #expect(back.clock.text(at: Fixture.at(50 * 60)) == match.clock.text(at: Fixture.at(50 * 60)))
        #expect(back.report.timeline == match.report.timeline)
    }

    @Test func anUnfinishedMatchIsStillThereAfterARelaunch() throws {
        let store = tempStore()
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        log.append(Fixture.event(600, .goal(side: .home, scorer: Fixture.home9.id)))
        // An explicit createdAt: the store writes ISO-8601, which is whole
        // seconds, so a Date() with sub-second parts is the one thing that
        // does not come back identical (harmless, but not what this test is
        // about).
        let inProgress = Match(setup: Fixture.setup, events: log, createdAt: Fixture.at(0))
        try store.saveCurrent(inProgress)

        // A relaunch: a brand-new store object reading the same directory.
        let afterRelaunch = try MatchStore(directory: store.directory).current()
        #expect(afterRelaunch == inProgress)
        #expect(afterRelaunch?.score.home == 1)
    }

    @Test func finishedMatchesComeBackNewestFirstAndDeleteCleanly() throws {
        let store = tempStore()
        let older = Match(setup: Fixture.setup, events: EventLog(), createdAt: Fixture.at(0))
        var cupSetup = Fixture.setup
        cupSetup.competition = "Cup final"
        let newer = Match(setup: cupSetup, events: EventLog(), createdAt: Fixture.at(86_400))
        try store.save(older)
        try store.save(newer)
        #expect(try store.all().map(\.id) == [newer.id, older.id])

        try store.delete(id: newer.id)
        #expect(try store.all().map(\.id) == [older.id])
    }

    @Test func clearingTheCurrentMatchLeavesTheFinishedOnesAlone() throws {
        let store = tempStore()
        try store.saveCurrent(Fixture.playedMatch())
        try store.save(Fixture.playedMatch())
        try store.clearCurrent()
        #expect(try store.current() == nil)
        #expect(try store.all().count == 1)
    }
}

@Suite("season stats")
struct SeasonStatsTests {
    @Test func seasonStatsFoldCardsAndGoalsAcrossReports() {
        let stats = SeasonStats.make(from: [Fixture.playedMatch(), Fixture.playedMatch()])
        #expect(stats.matches == 2)
        #expect(stats.goals == 4)
        #expect(stats.yellowCards == 2)
        #expect(stats.redCards == 2)
        #expect(stats.cardsPerMatch == 2.0)
    }

    @Test func anEmptySeasonIsAllZeroes() {
        let stats = SeasonStats.make(from: [])
        #expect(stats.matches == 0)
        #expect(stats.totalCards == 0)
        #expect(stats.cardsPerMatch == 0)
    }
}
