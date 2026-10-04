import Foundation
import Testing
@testable import RefKit

@Suite("match report")
struct ReportTests {
    @Test func theTimelineStampsAnEventInAddedTimeAsFortyFivePlusTwo() {
        let report = Fixture.playedMatch().report
        let added = report.timeline.first { $0.added > 0 }
        #expect(added?.stamp == "45+2'")
        #expect(added?.line == "45+2' Goal — ARS #11")
    }

    @Test func theTimelineIsChronologicalAndNamed() {
        let report = Fixture.playedMatch().report
        #expect(report.timeline.map(\.line) == [
            "12' Goal — RMC #9",
            "35' Yellow card — ARS #7",
            "45' Added time, 1st half: 2′",
            "45+2' Goal — ARS #11",
            "11' Red card — RMC #4",
        ])
    }

    @Test func halvesAndTotalsFoldFromTheSameLog() {
        let report = Fixture.playedMatch().report
        #expect(report.score.text == "1–1")
        #expect(report.halves.count == 2)
        #expect(report.halves[0].homeGoals == 1)
        #expect(report.halves[0].awayGoals == 1)
        #expect(report.halves[0].announcedAdded == 120)
        #expect(report.halves[1].homeGoals == 0)
        #expect(report.halves[1].awayGoals == 0)
        #expect(report.totals.yellowCards == 1)
        #expect(report.totals.redCards == 1)
    }

    @Test func aSecondYellowIsAlsoARed() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        log.append(Fixture.event(600, .secondYellow(side: .home, player: Fixture.home4.id)))
        let report = MatchReport.make(from: Match(setup: Fixture.setup, events: log))
        #expect(report.totals.yellowCards == 1)
        #expect(report.totals.redCards == 1)
    }

    @Test func shareTextReadsLikeARefereesReport() {
        let match = Fixture.playedMatch()
        let text = match.report.shareText(match: match)
        #expect(text.contains("Real Madrid Club 1–1 Arsenal"))
        #expect(text.contains("45+2' Goal — ARS #11"))
        #expect(text.contains("1 yellow, 1 red."))
        #expect(text.contains("Distance 8.5 km."))
    }
}
