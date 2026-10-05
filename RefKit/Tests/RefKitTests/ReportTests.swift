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
        log.append(Fixture.event(600, .secondYellow(side: .home, player: PlayerRef(Fixture.home4))))
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

@Suite("assistant referees")
struct AssistantRefereeTests {
    @Test func theirNamesAreOnTheReportAndOldSetupsHaveNone() throws {
        var match = Fixture.playedMatch()
        match.setup.ar1 = "Sam Lee"
        match.setup.ar2 = "  "
        #expect(MatchReport.assistants(match.setup) == "AR1 Sam Lee")
        #expect(match.report.shareText(match: match).contains("AR1 Sam Lee"))
        #expect(MatchReport.assistants(Fixture.setup) == nil)
    }

    @Test func aRemindersCrewFillsTheARs() throws {
        let game = try #require(ScheduledGame.parse(ScheduleImportTests.reminder).first)
        let setup = game.matchSetup()
        #expect(setup.ar1 == "Sam Assistant")
        #expect(setup.ar2 == nil)
    }
}

@Suite("season activity")
struct SeasonActivityTests {
    @Test func theSeasonAddsUpOnlyWhatEachMatchRecorded() {
        var a = Fixture.playedMatch()   // 8,540 m, HR 132 avg / 178 max, 720 kcal
        a.metrics?.steps = 10_000
        var b = Fixture.playedMatch()
        b.id = UUID()
        b.metrics = MatchMetrics(distanceMeters: 6_460, averageHeartRate: 140, maxHeartRate: 185,
                                 activeCalories: 500, steps: nil)
        var c = Fixture.playedMatch()   // no Health access: no metrics at all
        c.id = UUID()
        c.metrics = nil

        let activity = SeasonStats.make(from: [a, b, c]).activity
        #expect(activity.distanceMeters == 15_000)
        #expect(activity.distancePerMatch == 7_500)
        #expect(activity.steps == 10_000)
        #expect(activity.stepsPerMatch == 10_000)
        #expect(activity.averageHeartRate == 136)
        #expect(activity.maxHeartRate == 185)
        #expect(activity.activeCalories == 1_220)
        #expect(SeasonStats.make(from: [c]).activity.isEmpty)
    }
}

@Suite("scorers by side")
struct ScorersTests {
    @Test func eachSidesGoalsWithTheirMinutes() {
        let match = Fixture.playedMatch()   // home #9 at 11:30; away #11 at 45+2:10
        #expect(MatchReport.goals(for: .home, in: match) == ["#9 12'"])
        #expect(MatchReport.goals(for: .away, in: match) == ["#11 45+2'"])
    }
}
