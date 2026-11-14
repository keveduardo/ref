import Foundation
import Testing
@testable import RefKit

/// The phone's list, as the watch reads it.
@Suite("the assignment on the wire")
struct AssignmentWireTests {
    @Test func oneUnreadableSetupDoesNotEmptyTheList() throws {
        let good = Fixture.setup
        let data = try SyncPayload.encode(SyncPayload.Assignment(setups: [good, Fixture.setup]))
        // Spoil the second setup: a field with the wrong type.
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var setups = try #require(json["setups"] as? [[String: Any]])
        setups[1]["home"] = "not a team"
        json["setups"] = setups
        let spoiled = try JSONSerialization.data(withJSONObject: json)
        let read = try SyncPayload.decode(SyncPayload.Assignment.self, from: spoiled)
        #expect(read.setups.map(\.id) == [good.id])
    }

    @Test func anOlderListDoesNotReplaceANewerOne() {
        let older = SyncPayload.Assignment(setups: [], sentAt: Fixture.at(0))
        let newer = SyncPayload.Assignment(setups: [], sentAt: Fixture.at(60))
        #expect(!older.isNewer(than: newer.sentAt))
        #expect(newer.isNewer(than: older.sentAt))
        #expect(older.isNewer(than: nil))
        #expect(SyncPayload.Assignment(setups: [], sentAt: nil).isNewer(than: Fixture.at(60)))
    }
}
