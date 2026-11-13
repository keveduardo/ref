import Foundation
import Testing
@testable import RefKit

/// The fixes from the 2026-11-13 audit: what the phone does with a match the
/// watch puts back, a finished match it sends, and a swap mid-match.
@Suite("watch hand-off")
struct WatchHandoffTests {
    @Test func aMatchFromThePhonesListSurvivesBeingPutBack() {
        var handoff = WatchHandoff()
        let fixture = UUID()
        handoff.started(fixture, phoneHadIt: true)
        #expect(handoff.onWatch == [fixture])
        #expect(handoff.cancelled(fixture) == false)
        #expect(handoff.onWatch.isEmpty)
    }

    @Test func aQuickStartPutBackGoes() {
        var handoff = WatchHandoff()
        let quick = UUID()
        handoff.started(quick, phoneHadIt: false)
        #expect(handoff.cancelled(quick) == true)
        #expect(handoff.madeOnWatch.isEmpty)
    }

    @Test func aQuickStartStillGoesWhenTheIdleReportArrivesFirst() {
        var handoff = WatchHandoff()
        let quick = UUID()
        handoff.started(quick, phoneHadIt: false)
        handoff.running(nil)
        #expect(handoff.onWatch.isEmpty)
        #expect(handoff.cancelled(quick) == true)
    }

    @Test func runningKeepsOnlyTheMatchInHand() {
        var handoff = WatchHandoff()
        let a = UUID(), b = UUID()
        handoff.started(a, phoneHadIt: true)
        handoff.started(b, phoneHadIt: true)
        handoff.running(b)
        #expect(handoff.onWatch == [b])
    }

    // MARK: - A finished match back from the watch

    private func finished(_ setup: MatchSetup) -> Match {
        Match(setup: setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)),
            Fixture.event(600, .goal(side: .home, scorer: nil)),
            Fixture.event(2700, .halfEnd(half: 1)),
            Fixture.event(3600, .kickOff(half: 2)),
            Fixture.event(6300, .fullTime),
        ]))
    }

    @Test func namesGivenOnThePhoneAfterFullTimeAreKept() {
        let base = Fixture.setup
        let fromWatch = finished(base)
        var onPhone = fromWatch
        onPhone.setup.home.name = "Named later"
        let merged = onPhone.receivingFromWatch(fromWatch)
        #expect(merged.setup.home.name == "Named later")
        #expect(merged.events == fromWatch.events)
    }

    @Test func aLateGoalOnEitherSideSurvivesAndARedeliveryChangesNothing() {
        let base = Fixture.setup
        var fromWatch = finished(base)
        var onPhone = fromWatch
        let phoneGoal = Fixture.event(6000, .goal(side: .away, scorer: nil))
        onPhone.events.append(phoneGoal)
        let watchGoal = Fixture.event(6100, .goal(side: .home, scorer: nil))
        fromWatch.events.append(watchGoal)

        let merged = onPhone.receivingFromWatch(fromWatch)
        #expect(merged.events.contains(id: phoneGoal.id))
        #expect(merged.events.contains(id: watchGoal.id))
        #expect(merged.receivingFromWatch(fromWatch) == merged)
    }

    @Test func thePhoneKeepsMetricsWhenTheWatchSendsNone() {
        var onPhone = finished(Fixture.setup)
        onPhone.metrics = MatchMetrics(distanceMeters: 1_700)
        var fromWatch = onPhone
        fromWatch.metrics = nil
        #expect(onPhone.receivingFromWatch(fromWatch).metrics?.distanceMeters == 1_700)
    }

    // MARK: - Swap

    @Test func aSwapIsNotTakenOnceKickedOff() {
        let onWatch = Fixture.setup
        var phone = onWatch.swappingSides()
        phone.away.name = "Renamed"        // the old home team, renamed on the phone
        let merged = onWatch.applyingEdits(phone, kickedOff: true)
        #expect(merged.home.id == onWatch.home.id)
        #expect(merged.home.name == "Renamed")
        #expect(merged.away.id == onWatch.away.id)
    }

    @Test func aSwapBeforeKickOffIsTaken() {
        let onWatch = Fixture.setup
        let merged = onWatch.applyingEdits(onWatch.swappingSides(), kickedOff: false)
        #expect(merged.home.id == onWatch.away.id)
    }

    // MARK: - Crew

    @Test func anUnreadGamePageLeavesTheCrewUnknown() throws {
        let row = try #require(CGISchedule.rows(CGIScheduleTests.schedule).first)
        #expect(CGISchedule.game(row, page: nil)?.crewKnown == false)
        #expect(CGISchedule.game(row, page: "<html></html>")?.crewKnown == true)
    }
}
