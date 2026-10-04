import Foundation
import Testing
@testable import RefKit

/// The clock is the one piece of Ref that a referee, a player and a league
/// will all remember differently if it is wrong even once. These tests are
/// the contract: wall-clock anchors, a 45-minute face, added time as a
/// separate field, and a clock that never advances on its own.
@Suite("match clock")
struct MatchClockTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func clock(_ events: [(TimeInterval, MatchEvent.Kind)],
               config: ClockConfig = .adult) -> MatchClock {
        MatchClock.replay(config: config,
                          events: events.map { MatchEvent(at: at($0.0), kind: $0.1) })
    }

    @Test func countUpReadsWholeSecondsFromTheKickOff() {
        let c = clock([(0, .kickOff(half: 1))])
        #expect(c.elapsed(inHalf: 1, at: at(7)) == 7)
        #expect(c.text(at: at(7)) == "0:07")
        #expect(c.phase(at: at(7)) == .running(half: 1))
    }

    @Test func pastTheHalfLengthTheMainFieldFreezesAndAddedTimeCountsUp() {
        let c = clock([(0, .kickOff(half: 1))])
        let late = at(45 * 60 + 130)
        #expect(c.elapsed(inHalf: 1, at: late) == 45 * 60 + 130)
        #expect(c.overrun(inHalf: 1, at: late) == 130)
        #expect(c.text(at: late) == "45:00 +2:10")
    }

    @Test func aJumpInNowIsPlayedTimeNotLostTime() {
        // The view can sleep, the wrist goes down, the app relaunches — the
        // clock is dated from the kick-off, so ten minutes is ten minutes.
        let c = clock([(0, .kickOff(half: 1))])
        #expect(c.elapsed(inHalf: 1, at: at(600)) == 600)
        #expect(c.text(at: at(600)) == "10:00")
    }

    @Test func countdownShowsWhatIsLeftThenTheOverrun() {
        var config = ClockConfig.adult
        config.countsDown = true
        let c = clock([(0, .kickOff(half: 1))], config: config)
        #expect(c.text(at: at(60)) == "44:00")
        #expect(c.text(at: at(45 * 60 + 30)) == "0:00 +0:30")
    }

    @Test func cumulativeDisplayCarriesTheFirstHalfIntoTheSecond() {
        var config = ClockConfig.adult
        config.display = .cumulative
        let c = clock([
            (0, .kickOff(half: 1)),
            (45 * 60, .halfEnd(half: 1)),
            (60 * 60, .kickOff(half: 2)),
        ], config: config)
        #expect(c.text(at: at(60 * 60 + 150)) == "47:30")
        #expect(c.text(at: at(60 * 60 + 45 * 60 + 60)) == "90:00 +1:00")
    }

    @Test func halfTimeStopsTheFirstHalfAndTheSecondStartsFromZero() {
        let c = clock([
            (0, .kickOff(half: 1)),
            (45 * 60, .halfEnd(half: 1)),
            (60 * 60, .kickOff(half: 2)),
        ])
        let inBreak = at(45 * 60 + 600)
        #expect(c.elapsed(inHalf: 1, at: inBreak) == 45 * 60)
        #expect(c.phase(at: inBreak) == .halfTime(next: 2))
        #expect(c.halfTimeElapsed(at: inBreak) == 600)
        #expect(c.text(at: inBreak) == "45:00")

        let secondHalf = at(60 * 60 + 300)
        #expect(c.elapsed(inHalf: 2, at: secondHalf) == 300)
        #expect(c.phase(at: secondHalf) == .running(half: 2))
        #expect(c.text(at: secondHalf) == "5:00")
    }

    @Test func pausedTimeIsNotPlayedAndResumingContinuesFromThePause() {
        let c = clock([
            (0, .kickOff(half: 1)),
            (60, .clockPaused),
            (600, .clockResumed),
        ])
        #expect(c.elapsed(inHalf: 1, at: at(300)) == 60)
        #expect(c.phase(at: at(300)) == .paused(half: 1))
        #expect(c.elapsed(inHalf: 1, at: at(900)) == 60 + 300)
        #expect(c.phase(at: at(900)) == .running(half: 1))
    }

    @Test func fullTimeFreezesTheClock() {
        let c = clock([
            (0, .kickOff(half: 1)),
            (900, .fullTime),
        ])
        #expect(c.phase(at: at(2000)) == .fullTime)
        #expect(c.elapsed(at: at(2000)) == 900)
        #expect(c.text(at: at(2000)) == "15:00")
    }

    @Test func aClockAskedBeforeItsKickOffReadsZeroAndNeverNegative() {
        let c = clock([(100, .kickOff(half: 1))])
        #expect(c.elapsed(inHalf: 1, at: t0) == 0)
        #expect(c.text(at: t0) == "0:00")
        #expect(c.phase(at: t0) == .notStarted)
    }

    @Test func anAnnouncedAddedTimeIsRecordedButNotYetCounted() {
        let c = clock([
            (0, .kickOff(half: 1)),
            (45 * 60, .addedTime(half: 1, seconds: 120)),
        ])
        let aMinutePast = at(45 * 60 + 60)
        #expect(c.announcedAdded(half: 1, at: aMinutePast) == 120)
        #expect(c.text(at: aMinutePast) == "45:00 +1:00")
    }

    @Test func anchorsLaterThanTheAskCannotChangeTheAnswer() {
        // The replay contract: asking at `now` uses the anchors up to `now`,
        // so an event that arrived early, or a log replayed after the match
        // ended, reads exactly as the live clock did.
        let events: [(TimeInterval, MatchEvent.Kind)] = [
            (0, .kickOff(half: 1)),
            (40 * 60, .clockPaused),
            (42 * 60, .clockResumed),
            (45 * 60, .halfEnd(half: 1)),
            (60 * 60, .kickOff(half: 2)),
        ]
        let full = clock(events)
        let probes: [TimeInterval] = [30, 41 * 60, 50 * 60, 60 * 60 + 42]
        for probe in probes {
            let now = at(probe)
            let prefix = MatchClock.replay(
                config: .adult,
                events: events.filter { at($0.0) <= now }
                    .map { MatchEvent(at: at($0.0), kind: $0.1) })
            #expect(prefix.text(at: now) == full.text(at: now))
            #expect(prefix.phase(at: now) == full.phase(at: now))
        }
    }
}

@Suite("clock text")
struct ClockFormatTests {
    @Test func secondsAreAlwaysTwoDigits() {
        #expect(ClockFormat.mmss(0) == "0:00")
        #expect(ClockFormat.mmss(7) == "0:07")
        #expect(ClockFormat.mmss(59) == "0:59")
        #expect(ClockFormat.mmss(60) == "1:00")
        #expect(ClockFormat.mmss(45 * 60) == "45:00")
    }

    @Test func theOverrunFieldOnlyAppearsWhenThereIsOne() {
        #expect(ClockFormat.withAdded("45:00", overrun: 0) == "45:00")
        #expect(ClockFormat.withAdded("45:00", overrun: 130) == "45:00 +2:10")
    }
}
