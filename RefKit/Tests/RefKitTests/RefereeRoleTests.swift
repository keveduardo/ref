import Foundation
import Testing
@testable import RefKit

@Suite("the referee's own role")
struct RefereeRoleTests {
    @Test func theSchedulesWordsAreRead() {
        #expect(RefereeRole(scheduled: "Center") == .cr)
        #expect(RefereeRole(scheduled: "AR") == .ar)
        #expect(RefereeRole(scheduled: "ar2") == .ar2)
        #expect(RefereeRole(scheduled: "4th") == .fourth)
        #expect(RefereeRole(scheduled: "Mentor") == nil)
    }

    @Test func itTravelsAndAnOldSetupStillDecodes() throws {
        var setup = Fixture.setup
        setup.myRole = .ar1
        let back = try JSONDecoder().decode(MatchSetup.self, from: JSONEncoder().encode(setup))
        #expect(back.myRole == .ar1)

        // A setup written before roles existed, or with a role unknown here.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as! [String: Any]
        json["myRole"] = "Linesman"
        let unknown = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(unknown.myRole == nil)
        json.removeValue(forKey: "myRole")
        let old = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.myRole == nil)
    }

    @Test func thePhonesEditReachesTheWatch() {
        let base = Fixture.setup
        var edited = base
        edited.myRole = .cr
        #expect(base.applyingEdits(edited, kickedOff: true).myRole == .cr)
    }
}
