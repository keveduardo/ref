import Foundation
import Testing
@testable import RefKit

/// A quick start played at a scheduled game's time becomes that game.
@Suite("folding a quick start into its fixture")
struct QuickStartFoldTests {
    /// A fixture kicking off `minutes` after the quick start's kick-off (t0).
    static func fixture(at minutes: Int, crew: String = "A. Referee") -> Match {
        var setup = Fixture.setup
        setup.kickOff = Fixture.at(minutes * 60)
        setup.cr = crew
        setup.competition = "Girls 12U — Field 3"
        return Match(setup: setup)
    }

    /// Played from Quick start: placeholder teams, the events from t0.
    static func quick(color: TeamColor? = nil) -> Match {
        var played = Fixture.playedMatch()
        played.setup = MatchSetup(home: .placeholder(.home), away: .placeholder(.away),
                                  competition: "12U Girls", clock: .adult, halfTimeMinutes: 7)
        if let color { played.setup.setColor(color, for: .home) }
        return played
    }

    @Test func aGameKickingOffLateIsFound() {
        let fixture = Self.fixture(at: -20)
        #expect(QuickStartFold.target(for: Self.quick(), among: [fixture], onWatch: [])?.id == fixture.id)
    }

    @Test func tooEarlyOrTooLateIsNot() {
        // The quick start kicked off 20 minutes before this one — the game before it, more likely.
        #expect(QuickStartFold.target(for: Self.quick(), among: [Self.fixture(at: 20)], onWatch: []) == nil)
        #expect(QuickStartFold.target(for: Self.quick(), among: [Self.fixture(at: -60)], onWatch: []) == nil)
    }

    @Test func backToBackTheNearerWins() {
        // 6 PM and 7 PM; the quick start kicked off at 6:25.
        let six = Self.fixture(at: -25), seven = Self.fixture(at: 35)
        #expect(QuickStartFold.target(for: Self.quick(), among: [seven, six], onWatch: [])?.id == six.id)
    }

    @Test func aTieIsLeftAlone() {
        let a = Self.fixture(at: -10), b = Self.fixture(at: 10)
        #expect(QuickStartFold.target(for: Self.quick(), among: [a, b], onWatch: []) == nil)
    }

    @Test func playedStartedOrOnTheWatchIsSkipped() {
        let played = { var m = Fixture.playedMatch(); m.setup.kickOff = Fixture.t0; return m }()
        let onWatch = Self.fixture(at: 0)
        #expect(QuickStartFold.target(for: Self.quick(), among: [played, onWatch], onWatch: [onWatch.id]) == nil)
    }

    @Test func noKickOffNoFold() {
        var quick = Self.quick()
        quick.events = EventLog()
        #expect(QuickStartFold.target(for: quick, among: [Self.fixture(at: 0)], onWatch: []) == nil)
    }

    @Test func theFoldKeepsTheFixtureAndTheRecord() {
        let fixture = Self.fixture(at: -5)
        let quick = Self.quick(color: .green)
        let merged = QuickStartFold.fold(quick, into: fixture)
        #expect(merged.id == fixture.id)
        #expect(merged.setup.home.name == Fixture.home.name)
        #expect(merged.setup.cr == "A. Referee")
        #expect(merged.setup.competition == "Girls 12U — Field 3")
        #expect(merged.setup.clock == quick.setup.clock)
        #expect(merged.setup.halfTimeMinutes == 7)
        #expect(merged.events == quick.events)
        #expect(merged.metrics == quick.metrics)
        #expect(merged.clock.phase(at: Fixture.at(200 * 60)) == .fullTime)
        // Green was chosen on the watch; away kept the fixture's own.
        #expect(merged.setup.home.color == .green)
        #expect(merged.setup.away.color == Fixture.away.color)
    }
}
