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

@Suite("referees")
struct AssistantRefereeTests {
    @Test func theirNamesAreOnTheReportAndOldSetupsHaveNone() throws {
        var match = Fixture.playedMatch()
        match.setup.ar1 = "Sam Lee"
        match.setup.ar2 = "  "
        #expect(MatchReport.referees(match.setup) == "AR1 Sam Lee")
        #expect(match.report.shareText(match: match).contains("AR1 Sam Lee"))
        #expect(MatchReport.referees(Fixture.setup) == nil)
        match.setup.cr = "Alex Ruiz"
        #expect(MatchReport.referees(match.setup) == "CR Alex Ruiz · AR1 Sam Lee")
    }

    @Test func aSetupSavedBeforeTheCentreRefereeStillDecodes() throws {
        var old = Fixture.setup
        old.ar1 = "Sam Lee"
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "cr")
        let back = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.cr == nil && back.ar1 == "Sam Lee")
    }

    @Test func aRemindersCrewFillsTheARs() throws {
        let game = try #require(ScheduledGame.parse(ScheduleImportTests.reminder).first)
        let setup = game.matchSetup()
        #expect(setup.cr == "Pat Referee")
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

@Suite("goals added after the whistle")
struct LateGoalTests {
    @Test func afterFullTimeTheGoalIsTheLastHalfsLastMinute() throws {
        var match = Fixture.playedMatch()
        let whistle = try #require(match.events.lastWhistle)
        #expect(whistle.half == 2 && whistle.at == Fixture.at(105 * 60))
        match.events.append(EventLog.lateGoal(side: .away, scorer: PlayerRef(number: 7), beforeWhistle: whistle.at))
        #expect(match.report.score.away == 2)
        #expect(match.clock.phase(at: Fixture.at(106 * 60)) == .fullTime)
        let line = try #require(match.report.timeline.last { $0.text.contains("ARS") && $0.half == 2 })
        #expect(line.minute == 45 && line.added == 0)
        #expect(match.report.timeline.last?.text == line.text)   // after the red, in time order
    }

    @Test func atHalfTimeTheGoalIsTheFirstHalfsWithItsAddedTime() throws {
        var match = Fixture.playedMatch()
        let whistle = try #require(match.events.whistle(endingHalf: 1))
        match.events.append(EventLog.lateGoal(side: .home, scorer: nil, beforeWhistle: whistle))
        let goal = try #require(match.report.timeline.last { $0.half == 1 && $0.text.contains("Real Madrid") })
        #expect(goal.minute == 45 && goal.added == 2)
        #expect(match.report.halves.first?.homeGoals == 2)
    }

    @Test func noWhistleWhileAHalfRuns() {
        let running = EventLog(events: [Fixture.event(0, .kickOff(half: 1))])
        #expect(running.lastWhistle == nil)
        #expect(running.whistle(endingHalf: 1) == nil)
        #expect(Fixture.playedMatch().events.whistle(endingHalf: 2) == Fixture.at(105 * 60))
        #expect(Fixture.playedMatch().events.whistle(endingHalf: 3) == nil)
    }
}

@Suite("team number and coach")
struct TeamDetailsTests {
    @Test func theyAreOnTheReportAndOldTeamsHaveNone() throws {
        var match = Fixture.playedMatch()
        #expect(match.setup.home.details == nil)
        match.setup.home.number = "A1 02"
        match.setup.home.coach = "Smith"
        match.setup.away.coach = "  "
        #expect(match.setup.home.details == "Team A1 02 · Coach Smith")
        #expect(match.setup.away.details == nil)
        #expect(match.report.shareText(match: match).contains("Real Madrid Club: Team A1 02 · Coach Smith"))

        let old = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Old","abbreviation":"OLD","color":"red"}"#
        let team = try JSONDecoder().decode(Team.self, from: Data(old.utf8))
        #expect(team.number == nil && team.coach == nil)
    }
}
