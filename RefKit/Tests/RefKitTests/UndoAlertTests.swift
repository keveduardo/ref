import Foundation
import Testing
@testable import RefKit

@Suite("undo")
struct UndoTests {
    @Test func aVoidedGoalLeavesTheScoreTheReportAndTheUndoOffer() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        let goal = Fixture.event(600, .goal(side: .home, scorer: PlayerRef(Fixture.home9)))
        log.append(goal)
        #expect(log.lastUndoable?.id == goal.id)

        log.append(Fixture.event(610, .voided(goal.id)))
        let match = Match(setup: Fixture.setup, events: log)
        #expect(match.score.text == "0–0")
        #expect(match.report.timeline.isEmpty)
        #expect(log.lastUndoable == nil)
        // Nothing is removed: the goal and the void are both still recorded.
        #expect(log.recorded.count == 3)
        #expect(log.events.count == 1)
    }

    @Test func undoOffersTheNewestIncidentAndSkipsTheClocksAnchors() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        let yellow = Fixture.event(300, .yellowCard(side: .away, player: PlayerRef(Fixture.away7)))
        log.append(yellow)
        log.append(Fixture.event(45 * 60, .halfEnd(half: 1)))
        // The half end is not an incident; the yellow before it is.
        #expect(log.lastUndoable?.id == yellow.id)
    }

    @Test func resumingAHalfEndedByMistakePutsTheClockBackAsIfItNeverStopped() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        let end = Fixture.event(20 * 60, .halfEnd(half: 1))
        log.append(end)
        #expect(log.lastHalfEnd?.id == end.id)
        #expect(Match(setup: Fixture.setup, events: log).clock.phase(at: Fixture.at(21 * 60))
                == .halfTime(next: 2))

        log.append(Fixture.event(21 * 60, .voided(end.id)))
        let clock = Match(setup: Fixture.setup, events: log).clock
        #expect(clock.phase(at: Fixture.at(22 * 60)) == .running(half: 1))
        // The minute the whistle was wrongly blown was still played.
        #expect(clock.text(at: Fixture.at(22 * 60)) == "22:00")
        #expect(log.lastHalfEnd == nil)
    }

    @Test func thereIsNoHalfToResumeOnceTheNextOneKicksOff() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        log.append(Fixture.event(45 * 60, .halfEnd(half: 1)))
        log.append(Fixture.event(45 * 60, .addedTime(half: 1, seconds: 60)))
        #expect(log.lastHalfEnd != nil)
        log.append(Fixture.event(60 * 60, .kickOff(half: 2)))
        #expect(log.lastHalfEnd == nil)
    }

    @Test func aVoidSurvivesTheDiskFormatAndARedelivery() throws {
        var log = EventLog()
        let goal = Fixture.event(600, .goal(side: .away, scorer: nil))
        let void = Fixture.event(610, .voided(goal.id))
        log.append(goal)
        log.append(void)

        let data = try JSONEncoder().encode(log)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"events\""))
        var back = try JSONDecoder().decode(EventLog.self, from: data)
        #expect(back == log)

        // A finished match delivered twice merges into the same log.
        back.append(contentsOf: [goal, void])
        #expect(back.recorded.count == 2)
        #expect(back.events.isEmpty)
    }

    @Test func aSecondYellowIsRecognisedByIdOrByNumber() {
        var log = EventLog()
        log.append(Fixture.event(300, .yellowCard(side: .away, player: PlayerRef(Fixture.away7))))
        #expect(log.hasYellow(side: .away, player: PlayerRef(Fixture.away7)))
        #expect(log.hasYellow(side: .away, player: PlayerRef(number: 7)))
        // The other team's #7, and a player with no number, are not booked.
        #expect(!log.hasYellow(side: .home, player: PlayerRef(number: 7)))
        #expect(!log.hasYellow(side: .away, player: PlayerRef()))
    }

    @Test func theUndoLabelIsTheReportsOwnLine() {
        let text = MatchReport.text(for: .yellowCard(side: .away, player: PlayerRef(number: 7)),
                                    in: Match(setup: Fixture.setup))
        #expect(text == "Yellow card — ARS #7")
        #expect(MatchReport.text(for: .kickOff(half: 1), in: Match(setup: Fixture.setup)) == nil)
    }
}

@Suite("alerts")
struct AlertTests {
    func match(_ events: [(Int, MatchEvent.Kind)]) -> Match {
        Match(setup: Fixture.setup, events: EventLog(events: events.map { Fixture.event($0.0, $0.1) }))
    }

    @Test func theHalfLengthAndTheAddedTimeAreBothAhead() {
        let m = match([(0, .kickOff(half: 1)),
                       (44 * 60, .addedTime(half: 1, seconds: 120))])
        let alerts = m.upcomingAlerts(after: Fixture.at(44 * 60))
        #expect(alerts.map(\.kind) == [.halfLength(half: 1), .addedTimeUp(half: 1)])
        #expect(alerts.map(\.at) == [Fixture.at(45 * 60), Fixture.at(47 * 60)])
    }

    @Test func aSinBinIsFeltWhenThePlayerMayReturn() {
        let binEvent = Fixture.event(10 * 60, .sinBin(side: .home, player: PlayerRef(Fixture.home4), minutes: 10))
        let m = Match(setup: Fixture.setup,
                      events: EventLog(events: [Fixture.event(0, .kickOff(half: 1)), binEvent]))
        let alerts = m.upcomingAlerts(after: Fixture.at(12 * 60))
        #expect(alerts.first?.kind == .binOver(binID: binEvent.id, side: .home,
                                                player: PlayerRef(Fixture.home4)))
        #expect(alerts.first?.at == Fixture.at(20 * 60))
    }

    @Test func nothingIsProjectedWhileTheClockIsStopped() {
        // At half time the playing-time bin is frozen and no half is running.
        let m = match([(0, .kickOff(half: 1)),
                       (40 * 60, .sinBin(side: .home, player: PlayerRef(Fixture.home4), minutes: 10)),
                       (45 * 60, .halfEnd(half: 1))])
        #expect(m.upcomingAlerts(after: Fixture.at(50 * 60)).isEmpty)
    }

    @Test func passedMomentsAreNotAlertedAgain() {
        let m = match([(0, .kickOff(half: 1))])
        #expect(m.upcomingAlerts(after: Fixture.at(46 * 60)).isEmpty)
    }

    @Test func anUndoneBinIsNeverFelt() {
        let bin = Fixture.event(10 * 60, .sinBin(side: .home, player: PlayerRef(Fixture.home4), minutes: 10))
        let m = Match(setup: Fixture.setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)), bin, Fixture.event(10 * 60 + 5, .voided(bin.id))]))
        #expect(m.upcomingAlerts(after: Fixture.at(11 * 60)).map(\.kind) == [.halfLength(half: 1)])
    }
}

@Suite("defaults")
struct DefaultsTests {
    @Test func theSinBinLengthAndTheDefaultsTravelWithTheAssignment() throws {
        var setup = Fixture.setup
        setup.sinBinMinutes = 5
        let payload = SyncPayload.Assignment(setups: [setup],
                                             defaults: MatchDefaults(halfMinutes: 30, sinBinMinutes: 5))
        let back = try SyncPayload.decode(SyncPayload.Assignment.self,
                                          from: SyncPayload.encode(payload))
        #expect(back.setups.first?.sinBinMinutes == 5)
        #expect(back.defaults.halfMinutes == 30)
    }
}

@Suite("half-time")
struct HalfTimeTests {
    @Test func theBreakBuzzesWhenItsMinutesAreUp() {
        var setup = Fixture.setup
        setup.halfTimeMinutes = 5
        let m = Match(setup: setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)),
            Fixture.event(45 * 60, .halfEnd(half: 1))]))
        let alerts = m.upcomingAlerts(after: Fixture.at(46 * 60))
        #expect(alerts.map(\.kind) == [.halfTimeOver(next: 2)])
        #expect(alerts.first?.at == Fixture.at(50 * 60))
        // Once the break has run past it, nothing more.
        #expect(m.upcomingAlerts(after: Fixture.at(51 * 60)).isEmpty)
    }

    @Test func theBreakLengthIsTheMatchsOwn() {
        var setup = Fixture.setup
        setup.halfTimeMinutes = 10
        let m = Match(setup: setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)),
            Fixture.event(30 * 60, .halfEnd(half: 1))]))
        #expect(m.upcomingAlerts(after: Fixture.at(30 * 60)).first?.at == Fixture.at(40 * 60))
    }

    @Test func aSetupSavedBeforeHalfTimeExistedStillLoads() throws {
        // What build 22 wrote: no halfTimeMinutes, no formatID.
        var json = try JSONSerialization.jsonObject(
            with: SyncPayload.encode(Fixture.setup)) as! [String: Any]
        json.removeValue(forKey: "halfTimeMinutes")
        json.removeValue(forKey: "formatID")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.halfTimeMinutes == 5)
        #expect(old.home == Fixture.setup.home)

        let defaults = try JSONDecoder().decode(MatchDefaults.self,
                                                from: Data(#"{"halfMinutes":30,"sinBinMinutes":10}"#.utf8))
        #expect(defaults.halfTimeMinutes == 5)
        #expect(defaults.halfMinutes == 30)
    }
}

@Suite("metrics")
struct MetricsTests {
    @Test func stepsReachTheShareTextAndOldRecordsStillDecode() throws {
        var match = Fixture.playedMatch()
        match.metrics?.steps = 9_876
        #expect(match.report.shareText(match: match).contains("9,876 steps."))

        // A record from before steps were counted.
        let old = try JSONDecoder().decode(MatchMetrics.self,
                                           from: Data(#"{"distanceMeters":8540,"averageHeartRate":132}"#.utf8))
        #expect(old.steps == nil)
        #expect(old.distanceMeters == 8_540)
    }
}

@Suite("added time button")
struct AddedTimeButtonTests {
    @Test func offUnlessAskedForAndOffForOldRecords() throws {
        #expect(!Fixture.setup.addedTimeButton)
        #expect(!MatchDefaults.standard.addedTimeButton)
        var json = try JSONSerialization.jsonObject(with: SyncPayload.encode(Fixture.setup)) as! [String: Any]
        json.removeValue(forKey: "addedTimeButton")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!old.addedTimeButton)

        var on = Fixture.setup
        on.addedTimeButton = true
        let back = try SyncPayload.decode(SyncPayload.Assignment.self,
                                          from: SyncPayload.encode(SyncPayload.Assignment(setups: [on])))
        #expect(back.setups.first?.addedTimeButton == true)
    }
}

@Suite("quarter breaks")
struct QuarterBreakTests {
    static var setup: MatchSetup {
        var s = Fixture.setup
        s.clock = ClockConfig(halfMinutes: 25)
        s.quarterBreak = QuarterBreak(breakMinutes: 2)
        return s
    }

    @Test func theMarkIsMidwayUnlessAMinuteIsChosen() {
        #expect(QuarterBreak().mark(halfLength: TimeInterval(25 * 60)) == TimeInterval(12 * 60))
        #expect(QuarterBreak().mark(halfLength: TimeInterval(30 * 60)) == TimeInterval(15 * 60))
        #expect(QuarterBreak(atMinute: 10).mark(halfLength: TimeInterval(25 * 60)) == TimeInterval(10 * 60))
    }

    @Test func theWatchBuzzesAtTheQuarterMarkThenAtTheEndOfTheBreak() {
        var m = Match(setup: Self.setup, events: EventLog(events: [Fixture.event(0, .kickOff(half: 1))]))
        let first = m.upcomingAlerts(after: Fixture.at(60))
        #expect(first.first?.kind == .quarterMark(half: 1))
        #expect(first.first?.at == Fixture.at(12 * 60))

        // The break: the clock stops at 12:10, and two minutes later it buzzes.
        m.events.append(Fixture.event(12 * 60 + 10, .clockPaused))
        let during = m.upcomingAlerts(after: Fixture.at(12 * 60 + 30))
        #expect(during.map(\.kind) == [.quarterBreakOver(half: 1)])
        #expect(during.first?.at == Fixture.at(14 * 60 + 10))
        #expect(m.clock.pauseElapsed(at: Fixture.at(13 * 60 + 10)) == 60)

        // Resumed: no second quarter alert in this half, the half length next.
        m.events.append(Fixture.event(14 * 60 + 30, .clockResumed))
        let after = m.upcomingAlerts(after: Fixture.at(15 * 60))
        #expect(!after.contains { $0.kind == .quarterMark(half: 1) })
        #expect(after.first?.kind == .halfLength(half: 1))
        // The stopped time does not count: 12:10 played before, 30 s since.
        #expect(m.clock.text(at: Fixture.at(15 * 60)) == "12:40")
    }

    @Test func theSecondHalfHasItsOwnQuarter() {
        let m = Match(setup: Self.setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)),
            Fixture.event(12 * 60, .clockPaused),
            Fixture.event(14 * 60, .clockResumed),
            Fixture.event(27 * 60, .halfEnd(half: 1)),
            Fixture.event(32 * 60, .kickOff(half: 2))]))
        #expect(m.upcomingAlerts(after: Fixture.at(33 * 60)).first?.kind == .quarterMark(half: 2))
    }

    @Test func noQuarterBreakNoQuarterAlerts() {
        let m = Match(setup: Fixture.setup, events: EventLog(events: [Fixture.event(0, .kickOff(half: 1))]))
        #expect(!m.upcomingAlerts(after: Fixture.at(60)).contains { $0.kind == .quarterMark(half: 1) })
    }
}
