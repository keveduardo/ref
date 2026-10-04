import Foundation
import Testing
@testable import RefKit

@Suite("sync payloads")
struct SyncPayloadTests {
    @Test func aFinishedMatchSurvivesTheWire() throws {
        let payload = SyncPayload.FinishedMatch(match: Fixture.playedMatch())
        let data = try SyncPayload.encode(payload)
        let back = try SyncPayload.decode(SyncPayload.FinishedMatch.self, from: data)
        #expect(back == payload)
        #expect(back.match.metrics?.distanceMeters == 8_540)
        #expect(back.match.report.score.text == "1–1")
    }

    @Test func anAssignmentSurvivesTheWire() throws {
        let payload = SyncPayload.Assignment(setups: [Fixture.setup])
        let data = try SyncPayload.encode(payload)
        let back = try SyncPayload.decode(SyncPayload.Assignment.self, from: data)
        #expect(back == payload)
    }

    @Test func aPayloadFromAFutureVersionIsRefused() {
        let json = Data(#"{"version": 2, "setups": []}"#.utf8)
        #expect(throws: SyncPayload.Refusal.futureVersion(2)) {
            _ = try SyncPayload.decode(SyncPayload.Assignment.self, from: json)
        }
    }
}

@Suite("geo distance")
struct GeoDistanceTests {
    func point(_ latitude: Double, _ longitude: Double, accuracy: Double = 5) -> RoutePoint {
        RoutePoint(latitude: latitude, longitude: longitude, accuracy: accuracy,
                   at: Fixture.at(0))
    }

    @Test func distanceSumsConsecutiveLegs() {
        // A thousandth of a degree of latitude is ~111.2 m.
        let metres = GeoDistance.metres([point(0, 0), point(0.001, 0), point(0.002, 0)])
        #expect(abs(metres - 222.4) < 1)
    }

    @Test func aSingleFixHasNoDistance() {
        #expect(GeoDistance.metres([point(0, 0)]) == 0)
        #expect(GeoDistance.metres([]) == 0)
    }

    @Test func inaccurateFixesAreDroppedBeforeTheSum() {
        let raw = [point(0, 0, accuracy: 5),
                   point(0.001, 0, accuracy: 100),
                   point(0.002, 0, accuracy: 0)]
        let kept = GeoDistance.filtered(raw)
        #expect(kept.count == 1)
        #expect(GeoDistance.metres(kept) == 0)
    }
}

@Suite("editing a running match from the phone")
struct LiveEditTests {
    @Test func namesAndColoursAlwaysTheClockOnlyBeforeKickOff() {
        let running = MatchSetup(home: .placeholder(.home), away: .placeholder(.away),
                                 clock: ClockConfig(halfMinutes: 25))
        var edited = running
        edited.home = Team(id: running.home.id, name: "Sharks", abbreviation: "SHK", color: .green)
        edited.competition = "AYSO 10U Girls"
        edited.clock = ClockConfig(halfMinutes: 30)
        edited.quarterBreak = QuarterBreak()

        let live = running.applyingEdits(edited, kickedOff: true)
        #expect(live.home.name == "Sharks")
        #expect(live.home.color == .green)
        #expect(live.competition == "AYSO 10U Girls")
        #expect(live.clock.halfLength == TimeInterval(25 * 60))
        #expect(live.quarterBreak == nil)

        let before = running.applyingEdits(edited, kickedOff: false)
        #expect(before.clock.halfLength == TimeInterval(30 * 60))
        #expect(before.quarterBreak != nil)
    }

    @Test func anotherMatchsEditsAreIgnored() {
        let mine = MatchSetup(home: .placeholder(.home), away: .placeholder(.away))
        let other = MatchSetup(home: Team(name: "X"), away: Team(name: "Y"))
        #expect(mine.applyingEdits(other, kickedOff: false) == mine)
    }

    @Test func aStartedMatchSurvivesTheWire() throws {
        let payload = SyncPayload.StartedMatch(setup: Fixture.setup)
        let back = try SyncPayload.decode(SyncPayload.StartedMatch.self, from: SyncPayload.encode(payload))
        #expect(back == payload)
    }
}
