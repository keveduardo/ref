import Foundation
import Testing
@testable import RefKit

@Suite("event log")
struct EventLogTests {
    @Test func eventsArrivingLateAreSortedAndDeduplicatedById() {
        var log = EventLog()
        let kickOff = Fixture.event(0, .kickOff(half: 1))
        let goal = Fixture.event(100, .goal(side: .home, scorer: nil))
        let late = Fixture.event(50, .note("late arrival"))
        log.append(kickOff)
        log.append(goal)
        log.append(late)
        #expect(log.events.map(\.at) == [Fixture.at(0), Fixture.at(50), Fixture.at(100)])

        // The same event twice — a re-delivered sync payload — is one event.
        log.append(goal)
        #expect(log.events.count == 3)
        #expect(log.contains(id: goal.id))
    }
}

@Suite("score")
struct ScoreTests {
    @Test func goalsAndOwnGoalsCountForTheRightSide() {
        var log = EventLog()
        log.append(Fixture.event(0, .goal(side: .home, scorer: PlayerRef(Fixture.home9))))
        log.append(Fixture.event(60, .ownGoal(side: .away, scorer: PlayerRef(Fixture.away7))))
        let score = Score.from(log)
        // An own goal by the away side is a home goal.
        #expect(score.home == 2)
        #expect(score.away == 0)
        #expect(score.winner == .home)
        #expect(score.text == "2–0")
    }

    @Test func aDisallowedGoalIsOnTheTimelineButNotTheScore() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        log.append(Fixture.event(600, .disallowedGoal(side: .home)))
        let match = Match(setup: Fixture.setup, events: log)
        #expect(match.score.home == 0)
        #expect(match.report.timeline.contains { $0.text.contains("disallowed") })
    }

    @Test func aDrawHasNoWinner() {
        #expect(Score(home: 1, away: 1).winner == nil)
    }
}

@Suite("sin bins")
struct SinBinTests {
    func clock(_ events: [(Int, MatchEvent.Kind)]) -> MatchClock {
        MatchClock.replay(config: .adult,
                          events: events.map { Fixture.event($0.0, $0.1) })
    }

    @Test func aSinBinExpiresExactlyAtItsDuration() {
        let c = clock([(0, .kickOff(half: 1))])
        let bin = SinBin(side: .home, player: PlayerRef(Fixture.home4),
                         start: Fixture.at(600), minutes: 10, clock: .match)
        #expect(bin.remaining(at: Fixture.at(600 + 599), clock: c) == 1)
        #expect(bin.remaining(at: Fixture.at(600 + 600), clock: c) == 0)
        #expect(!bin.isActive(at: Fixture.at(600 + 600), clock: c))
    }

    @Test func aSinBinOnTheMatchClockPausesWithTheWhistle() {
        // Bin taken at 40:00. Half ends at 45:00; second half kicks off at
        // 60:00. At 65:00 — twenty-five wall minutes later — only ten minutes
        // of play have passed, so a ten-minute bin is over…
        let c = clock([(0, .kickOff(half: 1)),
                       (45 * 60, .halfEnd(half: 1)),
                       (60 * 60, .kickOff(half: 2))])
        let bin = SinBin(side: .home, player: PlayerRef(Fixture.home4),
                         start: Fixture.at(40 * 60), minutes: 10, clock: .match)
        // …but at half time itself, five minutes of play in, five remain.
        let atHalfTime = Fixture.at(45 * 60 + 300)
        #expect(bin.remaining(at: atHalfTime, clock: c) == 5 * 60)
        #expect(bin.isActive(at: atHalfTime, clock: c))
    }

    @Test func theTwoBinClocksDisagreeAcrossHalfTime() {
        // A bin taken at 40:00, ten minutes. The first half ends at 45:00 and
        // the second kicks off at 60:00, so at 47:00 — seven wall minutes in —
        // the wall bin has burned 7 minutes and the playing-time bin only 5.
        let c = clock([(0, .kickOff(half: 1)),
                       (45 * 60, .halfEnd(half: 1)),
                       (60 * 60, .kickOff(half: 2))])
        let start = Fixture.at(40 * 60)
        let wall = SinBin(side: .home, player: PlayerRef(Fixture.home4),
                          start: start, minutes: 10, clock: .wall)
        let playing = SinBin(side: .home, player: PlayerRef(Fixture.home4),
                             start: start, minutes: 10, clock: .match)
        let duringBreak = Fixture.at(47 * 60)
        #expect(wall.remaining(at: duringBreak, clock: c) == 3 * 60)
        #expect(playing.remaining(at: duringBreak, clock: c) == 5 * 60)
        // At 50:00 the wall bin is over; the playing-time bin still has five
        // minutes to burn — the whistle paused it.
        let at50 = Fixture.at(50 * 60)
        #expect(wall.remaining(at: at50, clock: c) == 0)
        #expect(playing.remaining(at: at50, clock: c) == 5 * 60)
        #expect(playing.isActive(at: at50, clock: c))
    }

    @Test func theLogListsItsSinBinsOldestFirst() {
        var log = EventLog()
        log.append(Fixture.event(0, .kickOff(half: 1)))
        log.append(Fixture.event(600, .sinBin(side: .home, player: PlayerRef(Fixture.home4), minutes: 10)))
        log.append(Fixture.event(1200, .sinBin(side: .away, player: PlayerRef(Fixture.away7), minutes: 5)))
        let bins = log.sinBins()
        #expect(bins.count == 2)
        #expect(bins.first?.side == .home)
        // ! The explicit TimeInterval(...) matters: in `#expect`, a `5 * 60`
        // against an *optional* left side stays an Int and compares unequal.
        #expect(bins.last?.duration == TimeInterval(5 * 60))
        #expect(bins.map(\.duration) == [TimeInterval(10 * 60), TimeInterval(5 * 60)])
    }
}
