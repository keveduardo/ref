import Foundation
import Testing
@testable import RefKit

/// Team colours chosen on the watch mid-match, and the phone's list that
/// crosses them on the way.
@Suite("team colours from the watch")
struct WatchColorTests {
    @Test func aColourChosenHereSurvivesAnOlderListFromThePhone() {
        var onWatch = Fixture.setup
        let phoneBefore = onWatch
        onWatch.setColor(.green, for: .home)
        var held: [TeamSide: TeamColor] = [.home: .green]

        // The phone has not heard yet: its copy still has the old colour.
        let merged = onWatch.applyingEdits(phoneBefore, kickedOff: true, holding: &held)
        #expect(merged.home.color == .green)
        #expect(held[.home] == .green)

        // The phone has it now: the hold is let go.
        var phoneAfter = phoneBefore
        phoneAfter.setColor(.green, for: .home)
        _ = merged.applyingEdits(phoneAfter, kickedOff: true, holding: &held)
        #expect(held.isEmpty)

        // And a later change on the phone comes through.
        phoneAfter.setColor(.purple, for: .home)
        #expect(merged.applyingEdits(phoneAfter, kickedOff: true, holding: &held).home.color == .purple)
    }

    @Test func theOtherSideStillFollowsThePhone() {
        let onWatch = Fixture.setup
        var phone = onWatch
        phone.setColor(.orange, for: .away)
        var held: [TeamSide: TeamColor] = [.home: .black]
        let merged = onWatch.applyingEdits(phone, kickedOff: true, holding: &held)
        #expect(merged.away.color == .orange && merged.home.color == .black)
    }
}
