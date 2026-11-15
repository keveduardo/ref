import Foundation
import Testing
@testable import RefKit

/// The half length, changed on the watch (a beach-cup match set up as
/// 2 × 30 that was really 2 × 25).
@Suite("half length from the watch")
struct WatchHalfLengthTests {
    @Test func settingItClampsToThePickersRange() {
        var setup = Fixture.setup
        setup.setHalfMinutes(25)
        #expect(setup.halfMinutes == 25 && setup.clock.halfLength == TimeInterval(25 * 60))
        setup.setHalfMinutes(2)
        #expect(setup.halfMinutes == 5)
        setup.setHalfMinutes(90)
        #expect(setup.halfMinutes == 45)
    }

    @Test func aLengthSetHereSurvivesAnOlderListFromThePhone() {
        var onWatch = Fixture.setup
        onWatch.setHalfMinutes(30)
        let phoneBefore = onWatch
        onWatch.setHalfMinutes(25)
        var colors: [TeamSide: TeamColor] = [:]
        var held: TimeInterval? = TimeInterval(25 * 60)

        // Before kick-off the phone's clock would otherwise win.
        let merged = onWatch.applyingEdits(phoneBefore, kickedOff: false, holding: &colors, holdingHalf: &held)
        #expect(merged.halfMinutes == 25)
        #expect(held == TimeInterval(25 * 60))

        // The phone has it now: the hold is let go…
        var phoneAfter = phoneBefore
        phoneAfter.setHalfMinutes(25)
        _ = merged.applyingEdits(phoneAfter, kickedOff: false, holding: &colors, holdingHalf: &held)
        #expect(held == nil)

        // …and a later change on the phone, before kick-off, comes through.
        phoneAfter.setHalfMinutes(35)
        #expect(merged.applyingEdits(phoneAfter, kickedOff: false, holding: &colors, holdingHalf: &held).halfMinutes == 35)
    }

    @Test func theTimeAlreadyPlayedStands() {
        var setup = Fixture.setup
        setup.clock = ClockConfig(halfMinutes: 30)
        var match = Match(setup: setup, events: EventLog(events: [Fixture.event(0, .kickOff(half: 1))]))
        let at = Fixture.at(12 * 60)
        let before = match.clock.elapsed(inHalf: 1, at: at)
        match.setup.setHalfMinutes(25)
        #expect(match.clock.elapsed(inHalf: 1, at: at) == before)
        #expect(match.clock.config.halfLength == TimeInterval(25 * 60))
    }
}
