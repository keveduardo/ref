import Foundation
import Testing
@testable import RefKit

/// Pinned to the AYSO National Rules & Regulations (01/2020), Article I —
/// and to the division table printed on AYSO's paper match report.
@Suite("match formats")
struct MatchFormatTests {
    @Test func theAYSODivisionsMatchTheRulebook() throws {
        let u10 = try #require(MatchFormat.preset(id: "ayso-10u-girls"))
        #expect(u10.halfMinutes == 25)
        #expect(u10.playersPerSide == 7)
        #expect(u10.ballSize == 4)
        #expect(!u10.headingAllowed)
        #expect(!u10.keeperMayPunt)
        #expect(u10.buildOutLine)

        let u12 = try #require(MatchFormat.preset(id: "ayso-12u-boys"))
        #expect(u12.halfMinutes == 30)
        #expect(u12.playersPerSide == 9)
        #expect(u12.ballSize == 4)
        #expect(!u12.headingAllowed)
        #expect(u12.keeperMayPunt)
        #expect(!u12.buildOutLine)

        let u14 = try #require(MatchFormat.preset(id: "ayso-14u-girls"))
        #expect(u14.halfMinutes == 35)
        #expect(u14.playersPerSide == 11)
        #expect(u14.ballSize == 5)
        #expect(u14.headingAllowed)
        #expect(u14.halfTimeMinutes == 5...10)
    }

    @Test func girlsAndBoysShareTheRulesButNotTheName() throws {
        let girls = try #require(MatchFormat.preset(id: "ayso-12u-girls"))
        let boys = try #require(MatchFormat.preset(id: "ayso-12u-boys"))
        #expect(girls.title == "AYSO 12U Girls")
        #expect(boys.title == "AYSO 12U Boys")
        #expect(girls.halfMinutes == boys.halfMinutes)
        #expect(girls.playersPerSide == boys.playersPerSide)
    }

    @Test func thePickerOffersSixInAgeOrder() {
        #expect(MatchFormat.presets.map(\.title) == [
            "AYSO 10U Girls", "AYSO 10U Boys", "AYSO 12U Girls",
            "AYSO 12U Boys", "AYSO 14U Girls", "AYSO 14U Boys"])
    }

    @Test func theReminderSaysWhatIsDifferent() throws {
        let u10 = try #require(MatchFormat.preset(id: "ayso-10u-boys"))
        #expect(u10.reminder == "7 a side · size 4 ball · no heading · no punts · build-out line · half-time 5–10 min")
    }

    @Test func aSetupKeepsItsFormatAcrossTheWireAndDecodesWithoutOne() throws {
        var setup = Fixture.setup
        setup.formatID = "ayso-14u-boys"
        let back = try SyncPayload.decode(SyncPayload.Assignment.self,
                                          from: SyncPayload.encode(SyncPayload.Assignment(setups: [setup])))
        #expect(back.setups.first?.format?.title == "AYSO 14U Boys")
        #expect(Fixture.setup.format == nil)
    }
}
