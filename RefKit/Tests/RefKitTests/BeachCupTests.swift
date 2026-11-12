import Foundation
import Testing
@testable import RefKit

/// The Beach Cup tournament's half lengths, from its rules sheet.
@Suite("Beach Cup tournament")
struct BeachCupTests {
    @Test func theSheetsTable() {
        let table: [(BeachCupRound, [Int])] = [
            (.pool, [20, 25, 25]),
            (.quarterFinal, [20, 25, 30]),
            (.semiFinal, [25, 30, 35]),
            (.final, [25, 30, 35]),
        ]
        for (round, minutes) in table {
            #expect(BeachCupRound.ages.map { round.halfMinutes(age: $0) } == minutes, "\(round.title)")
        }
    }

    @Test func agesTheSheetLeavesOut() {
        #expect(BeachCupRound.pool.halfMinutes(age: 8) == nil)
        #expect(BeachCupRound.final.halfMinutes(age: 16) == nil)
    }

    @Test func theRoundTravelsAndAnOldSetupStillDecodes() throws {
        var setup = Fixture.setup
        setup.beachCup = .semiFinal
        let back = try JSONDecoder().decode(MatchSetup.self, from: JSONEncoder().encode(setup))
        #expect(back.beachCup == .semiFinal)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as! [String: Any]
        json.removeValue(forKey: "beachCup")
        #expect(try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json)).beachCup == nil)
    }
}
