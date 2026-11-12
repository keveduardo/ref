import Foundation
import Testing
@testable import RefKit

/// A scheduled game nobody started retires a day after its kick-off.
@Suite("retiring missed games")
struct RetireTests {
    static func scheduled(kickOff: Date?) -> Match {
        var setup = Fixture.setup
        setup.kickOff = kickOff
        return Match(setup: setup)
    }

    @Test func aDayPastKickOffItRetires() {
        let match = Self.scheduled(kickOff: Fixture.t0)
        #expect(!match.isRetired(at: Fixture.at(23 * 3600)))
        #expect(match.isRetired(at: Fixture.at(25 * 3600)))
    }

    @Test func noKickOffNeverRetires() {
        #expect(!Self.scheduled(kickOff: nil).isRetired(at: Fixture.at(30 * 24 * 3600)))
    }

    @Test func aStartedOrPlayedGameNeverRetires() {
        var started = Self.scheduled(kickOff: Fixture.t0)
        started.events = EventLog(events: [Fixture.event(0, .kickOff(half: 1))])
        #expect(!started.isRetired(at: Fixture.at(30 * 24 * 3600)))
        var played = Fixture.playedMatch()
        played.setup.kickOff = Fixture.t0
        #expect(!played.isRetired(at: Fixture.at(30 * 24 * 3600)))
    }
}
