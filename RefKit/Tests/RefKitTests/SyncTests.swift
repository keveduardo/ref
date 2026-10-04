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
