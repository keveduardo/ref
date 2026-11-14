import Foundation
import Testing
@testable import RefKit

/// 2026-11-14: a finished match the phone never got is sent again when the
/// phone says it is still waiting on it — and only then.
@Suite("sending a lost result again")
struct WatchResendTests {
    static let later = Fixture.at(4 * 3600)

    static func played(_ setup: MatchSetup = Fixture.setup) -> Match {
        Match(setup: setup, events: EventLog(events: [
            Fixture.event(0, .kickOff(half: 1)),
            Fixture.event(2700, .halfEnd(half: 1)),
            Fixture.event(3600, .kickOff(half: 2)),
            Fixture.event(6300, .fullTime),
        ]))
    }

    @Test func aFinishedMatchThePhoneIsWaitingOnGoesAgain() {
        let lost = Self.played()
        let resend = WatchResend.toResend(shelf: [lost], awaiting: [lost.id], inHand: nil, at: Self.later)
        #expect(resend.map(\.id) == [lost.id])
    }

    @Test func oneThePhoneHasOrDeletedDoesNot() {
        let delivered = Self.played()
        #expect(WatchResend.toResend(shelf: [delivered], awaiting: [], inHand: nil, at: Self.later).isEmpty)
    }

    @Test func notTheMatchInHandNorOneUnfinished() {
        var running = Self.played()
        running.events = EventLog(events: [Fixture.event(0, .kickOff(half: 1))])
        #expect(WatchResend.toResend(shelf: [running], awaiting: [running.id], inHand: nil,
                                     at: Fixture.at(60)).isEmpty)
        let finished = Self.played()
        #expect(WatchResend.toResend(shelf: [finished], awaiting: [finished.id], inHand: finished.id,
                                     at: Self.later).isEmpty)
    }

    @Test func anOlderPhonesListStillReads() throws {
        let old = SyncPayload.Assignment(setups: [Fixture.setup])
        var json = String(decoding: try SyncPayload.encode(old), as: UTF8.self)
        json = json.replacingOccurrences(of: #","awaitingResults":null"#, with: "")
        let back = try SyncPayload.decode(SyncPayload.Assignment.self, from: Data(json.utf8))
        #expect(back.awaitingResults == nil)
        let id = UUID()
        let new = SyncPayload.Assignment(setups: [], awaitingResults: [id])
        #expect(try SyncPayload.decode(SyncPayload.Assignment.self, from: SyncPayload.encode(new))
                .awaitingResults == [id])
    }

    @Test func theShelfKeepsALateGoalAnOlderCopyWouldDrop() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MatchStore(directory: dir)
        let base = Self.played()
        var withGoal = base
        let goal = Fixture.event(6290, .goal(side: .home, scorer: nil))
        withGoal.events.append(goal)
        try store.saveUnion(withGoal)          // "Add goal" on the summary
        var older = base                        // the full-time copy, with numbers
        older.metrics = MatchMetrics(distanceMeters: 5_000)
        try store.saveUnion(older)
        let shelved = try store.load(id: base.id)
        #expect(shelved.events.contains(id: goal.id))
        #expect(shelved.metrics?.distanceMeters == 5_000)
    }
}
