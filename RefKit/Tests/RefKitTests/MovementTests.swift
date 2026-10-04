import Foundation
import Testing
@testable import RefKit

@Suite("movement")
struct MovementTests {
    /// A field in Redondo Beach, its length running north-east.
    static let frame = PitchFrame(latitude: 33.85, longitude: -118.38, bearing: 45, marked: true)
    static let size = PitchSize.adult

    /// A first half from 0 to 45:00, kicked off at t0.
    static var clock: MatchClock {
        MatchClock.replay(config: .adult, events: [
            Fixture.event(0, .kickOff(half: 1)), Fixture.event(45 * 60, .halfEnd(half: 1))])
    }

    @Test func projectionAndItsInverseAgree() {
        let p = Self.frame.point(x: 30, y: -12, at: Fixture.at(0))
        let back = Self.frame.project(p)
        #expect(abs(back.x - 30) < 0.01)
        #expect(abs(back.y + 12) < 0.01)
    }

    @Test func facingTheBearingIsPlusX() {
        // 10 m due north of the centre spot, with the bearing due north.
        let frame = PitchFrame(latitude: 33.85, longitude: -118.38, bearing: 0, marked: true)
        let north = RoutePoint(latitude: 33.85 + 10 / 111_320.0, longitude: -118.38,
                               accuracy: 5, at: Fixture.at(0))
        let p = frame.project(north)
        #expect(abs(p.x - 10) < 0.01)
        #expect(abs(p.y) < 0.01)
    }

    @Test func theFieldIsWorkedOutFromADiagonalRun() throws {
        // Up and down the diagonal for twenty minutes, one fix every 2 s.
        var route: [RoutePoint] = []
        for i in 0..<600 {
            let phase = Double(i % 60) / 60
            let along = (phase < 0.5 ? phase : 1 - phase) * 4 - 1  // -1…1…-1
            route.append(Self.frame.point(x: along * 40, y: along * 20, at: Fixture.at(i * 2)))
        }
        let inferred = try #require(PitchFrame.inferred(from: route))
        #expect(!inferred.marked)
        // The diagonal leans 26.6° off the length; the route's long axis is
        // the diagonal, so the inferred bearing is within that of the field's.
        let off = abs(inferred.bearing - Self.frame.bearing)
        #expect(min(off, 180 - off) < 30)
        let centre = Self.frame.project(RoutePoint(latitude: inferred.latitude,
                                                   longitude: inferred.longitude,
                                                   accuracy: 5, at: Fixture.at(0)))
        #expect(abs(centre.x) < 2 && abs(centre.y) < 2)
    }

    @Test func timeLandsInTheRightCellsAndThirds() {
        // Ten minutes standing just inside the far penalty area, then ten at
        // the centre spot.
        var route: [RoutePoint] = []
        for i in 0..<300 { route.append(Self.frame.point(x: 40, y: 0, at: Fixture.at(i * 2))) }
        for i in 300..<600 { route.append(Self.frame.point(x: 0, y: 0, at: Fixture.at(i * 2))) }
        let report = MovementReport.make(points: route, frame: Self.frame, size: Self.size,
                                         clock: Self.clock)
        #expect(abs(report.thirds[2] - 0.5) < 0.01)
        #expect(abs(report.thirds[1] - 0.5) < 0.01)
        #expect(report.thirds[0] == 0)
        // Two hot cells, nothing anywhere else.
        #expect(report.heat.filter { $0 > 0 }.count == 2)
        #expect(report.outside == 0)
    }

    @Test func distanceSprintsAndTopSpeed() {
        // Jog at 2 m/s for 60 s, sprint at 7 m/s for 6 s, jog again.
        var route: [RoutePoint] = []
        var x = -30.0
        for second in 0..<120 {
            route.append(Self.frame.point(x: x, y: 0, at: Fixture.at(second)))
            x += (60..<66).contains(second) ? 7 : 2
            if x > 50 { x = -30 }
        }
        let report = MovementReport.make(points: route, frame: Self.frame, size: Self.size,
                                         clock: Self.clock)
        #expect(report.sprints == 1)
        #expect(report.topSpeed > 6 && report.topSpeed < 7.5)
        #expect(report.distanceByHalf[0] > 200)
        #expect(report.distanceByHalf[1] == 0)
    }

    @Test func onlyRunningClockTimeCounts() {
        // Every fix during the break — none of it is the match.
        let route = (0..<100).map { Self.frame.point(x: 0, y: 0, at: Fixture.at(46 * 60 + $0 * 2)) }
        let report = MovementReport.make(points: route, frame: Self.frame, size: Self.size,
                                         clock: Self.clock)
        #expect(report.hottest == 0)
        #expect(report.distanceByHalf.reduce(0, +) == 0)
    }

    @Test func aGPSJumpIsNotASprint() {
        var route = (0..<60).map { Self.frame.point(x: 0, y: Double($0) * 0.5, at: Fixture.at($0)) }
        route[30] = Self.frame.point(x: 60, y: 0, at: Fixture.at(30))  // 60 m in a second
        let report = MovementReport.make(points: route, frame: Self.frame, size: Self.size,
                                         clock: Self.clock)
        #expect(report.sprints == 0)
        #expect(report.topSpeed < 10)
    }

    @Test func theDivisionsDrawTheirOwnFields() throws {
        let u10 = try #require(MatchFormat.preset(id: "ayso-10u-girls")).pitch
        let u14 = try #require(MatchFormat.preset(id: "ayso-14u-boys")).pitch
        let u19 = try #require(MatchFormat.preset(id: "ayso-19u-boys")).pitch
        #expect(u19 == .adult)
        #expect(abs(u10.length - 54.86) < 0.1)
        #expect(abs(u10.width - 36.58) < 0.1)
        #expect(abs(u14.length - 100.58) < 0.1)
        #expect(Fixture.setup.pitchSize == .adult)
    }

    @Test func aMatchKeepsItsMarkedField() throws {
        var match = Fixture.playedMatch()
        match.pitch = Self.frame
        let back = try SyncPayload.decode(SyncPayload.FinishedMatch.self,
                                          from: SyncPayload.encode(SyncPayload.FinishedMatch(match: match)))
        #expect(back.match.pitch == Self.frame)
    }
}

@Suite("route payload")
struct RoutePayloadTests {
    @Test func aRouteIsThinnedAndSurvivesTheWire() throws {
        let frame = MovementTests.frame
        let raw = (0..<600).map { frame.point(x: Double($0) / 10, y: 0, at: Fixture.at($0)) }
        let thinned = SyncPayload.Route.thinned(raw)
        #expect(thinned.count == 300)
        let payload = SyncPayload.Route(matchID: Fixture.setup.id, points: thinned)
        let back = try SyncPayload.decode(SyncPayload.Route.self, from: SyncPayload.encode(payload))
        #expect(back.matchID == payload.matchID)
        #expect(back.points.count == 300)
    }
}

@Suite("resolving the frame")
struct FrameResolveTests {
    static let route = (0..<100).map {
        MovementTests.frame.point(x: Double($0 % 50) - 25, y: Double($0 % 50) / 5, at: Fixture.at($0 * 2))
    }

    @Test func aMarkedFieldWins() {
        #expect(PitchFrame.resolve(marked: MovementTests.frame, route: Self.route) == MovementTests.frame)
    }

    @Test func aCentreWithoutACompassTakesTheRoutesDirection() throws {
        let centreOnly = PitchFrame(latitude: 33.85, longitude: -118.38, bearing: 0, marked: false)
        let resolved = try #require(PitchFrame.resolve(marked: centreOnly, route: Self.route))
        #expect(resolved.latitude == 33.85 && resolved.longitude == -118.38)
        #expect(resolved.bearing == PitchFrame.inferred(from: Self.route)?.bearing)
    }

    @Test func noMarkAtAllIsTheRoutesOwnFrame() {
        #expect(PitchFrame.resolve(marked: nil, route: Self.route) == PitchFrame.inferred(from: Self.route))
        #expect(PitchFrame.resolve(marked: nil, route: []) == nil)
    }
}
