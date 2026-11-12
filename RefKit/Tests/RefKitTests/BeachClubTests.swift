import Foundation
import Testing
@testable import RefKit

/// The Beach Club tournament's half lengths, from its rules sheet.
@Suite("Beach Club tournament")
struct BeachClubTests {
    @Test func theSheetsTable() {
        let table: [(BeachClubRound, [Int])] = [
            (.pool, [20, 25, 25]),
            (.quarterFinal, [20, 25, 30]),
            (.semiFinal, [25, 30, 35]),
            (.final, [25, 30, 35]),
        ]
        for (round, minutes) in table {
            #expect(BeachClubRound.ages.map { round.halfMinutes(age: $0) } == minutes, "\(round.title)")
        }
    }

    @Test func agesTheSheetLeavesOut() {
        #expect(BeachClubRound.pool.halfMinutes(age: 8) == nil)
        #expect(BeachClubRound.final.halfMinutes(age: 16) == nil)
    }

    @Test func theRoundTravelsAndAnOldSetupStillDecodes() throws {
        var setup = Fixture.setup
        setup.beachClub = .semiFinal
        let back = try JSONDecoder().decode(MatchSetup.self, from: JSONEncoder().encode(setup))
        #expect(back.beachClub == .semiFinal)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as! [String: Any]
        json.removeValue(forKey: "beachClub")
        #expect(try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json)).beachClub == nil)
    }
}
