import Foundation
import Testing
@testable import RefKit

/// Kevin, 2026-11-13: the map should know an assistant's movement from a
/// centre referee's — a touchline in one half, not the diagonal.
@Suite("assistant referee movement")
struct AssistantMovementTests {
    static let truth = MovementTests.frame
    static let size = PitchSize.adult

    /// Up and down the right touchline, halfway line to goal line, with a
    /// little wander off the line.
    static var touchlineRun: [RoutePoint] {
        (0..<1200).map { i in
            let along = Double(i % 200) / 200 * 52      // 0…52 m and back
            let x = (i / 200) % 2 == 0 ? along : 52 - along
            let y = -34 + Double(i % 7) * 0.3 - 1         // on the line, ±1 m
            return truth.point(x: x, y: y, at: Fixture.at(i))
        }
    }

    @Test func anAssistantsRunIsPutOnATouchlineInOneHalf() throws {
        let frame = try #require(PitchFrame.inferred(from: Self.touchlineRun, role: .ar1, size: Self.size))
        let projected = Self.touchlineRun.map { frame.project($0) }
        let xs = projected.map(\.x), ys = projected.map(\.y)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        // In one half, around its middle (either half: the route can't say).
        #expect(abs(abs(meanX) - Self.size.length / 4) < 5)
        // Along a touchline, not through the middle.
        #expect(abs(abs(meanY) - Self.size.width / 2) < 3)
    }

    @Test func theSameRunReadAsACentreRefereeSitsMidfield() throws {
        let frame = try #require(PitchFrame.inferred(from: Self.touchlineRun, role: .cr, size: Self.size))
        let ys = Self.touchlineRun.map { frame.project($0).y }
        #expect(abs(ys.reduce(0, +) / Double(ys.count)) < 3)
        #expect(frame == PitchFrame.inferred(from: Self.touchlineRun))
    }

    @Test func anAssistantWhoChangedEndsIsCentredOnHalfway() throws {
        let both = (0..<1200).map { i in
            Self.truth.point(x: Double(i % 200) / 200 * 100 - 50, y: -34, at: Fixture.at(i))
        }
        let frame = try #require(PitchFrame.inferred(from: both, role: .ar, size: Self.size))
        let xs = both.map { frame.project($0).x }
        #expect(abs(xs.reduce(0, +) / Double(xs.count)) < 5)
    }

    @Test func theReportCountsTimeOnTheTouchline() throws {
        let frame = try #require(PitchFrame.inferred(from: Self.touchlineRun, role: .ar2, size: Self.size))
        let clock = MatchClock.replay(config: ClockConfig(halfMinutes: 45), events: [
            Fixture.event(0, .kickOff(half: 1)),
        ])
        let report = MovementReport.make(points: Self.touchlineRun, frame: frame, size: Self.size, clock: clock)
        #expect(report.onTouchline > 0.9)
        #expect(report.outside < 0.1)
    }

    @Test func aMarkedFieldIsKeptWhateverTheRole() {
        #expect(PitchFrame.resolve(marked: Self.truth, route: Self.touchlineRun, role: .ar1, size: Self.size)
                == Self.truth)
    }

    @Test func onlyTheARsAreAssistants() {
        #expect(RefereeRole.ar.isAssistant && RefereeRole.ar1.isAssistant && RefereeRole.ar2.isAssistant)
        #expect(!RefereeRole.cr.isAssistant && !RefereeRole.fourth.isAssistant)
    }
}
