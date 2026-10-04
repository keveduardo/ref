import Foundation
import Testing
@testable import RefKit

/// Pinned to AYSO Region 34's Local Rules and Guidelines (2024 Fall Season),
/// row by row, and to the national rules for what that sheet leaves out.
@Suite("match formats")
struct MatchFormatTests {
    func preset(_ id: String) throws -> MatchFormat {
        try #require(MatchFormat.preset(id: id))
    }

    @Test func everyDivisionMatchesRegion34sTable() throws {
        // (age, half, players, min, ball, keepers, score, all IFK, build-out, offside, qtr subs, cards)
        let table: [(Int, Int, Int, Int, Int, Bool, Bool, Bool, Bool, Bool, Bool, Bool)] = [
            (7, 20, 7, 5, 3, false, false, true, true, false, true, false),
            (8, 20, 7, 5, 3, true, false, true, true, false, true, false),
            (10, 25, 8, 6, 4, true, true, false, true, true, true, false),
            (12, 30, 9, 7, 4, true, true, false, false, true, true, true),
            (14, 35, 11, 7, 5, true, true, false, false, true, true, true),
            (16, 40, 11, 7, 5, true, true, false, false, true, false, true),
            (19, 45, 11, 7, 5, true, true, false, false, true, false, true),
        ]
        for row in table where MatchFormat.ages.contains(row.0) {
            for gender in ["girls", "boys"] {
                let f = try preset("ayso-\(row.0)u-\(gender)")
                #expect(f.halfMinutes == row.1, "\(f.title) half")
                #expect(f.playersPerSide == row.2, "\(f.title) players")
                #expect(f.minimumPlayers == row.3, "\(f.title) minimum")
                #expect(f.ballSize == row.4, "\(f.title) ball")
                #expect(f.goalkeepers == row.5, "\(f.title) keepers")
                #expect(f.keepsScore == row.6, "\(f.title) score")
                #expect(f.allFoulsIndirect == row.7, "\(f.title) IFK")
                #expect(f.buildOutLine == row.8, "\(f.title) build-out")
                #expect((f.offsideLine != nil) == row.9, "\(f.title) offside")
                #expect(f.quarterSubstitutions == row.10, "\(f.title) subs")
                #expect(f.showsCards == row.11, "\(f.title) cards")
                #expect(f.halfTimeMinutes == 5...10)
            }
        }
    }

    @Test func headingAndPuntsFollowTheNationalRules() throws {
        #expect(try !preset("ayso-12u-girls").headingAllowed)
        #expect(try preset("ayso-14u-girls").headingAllowed)
        #expect(try !preset("ayso-10u-boys").keeperMayPunt)
        #expect(try preset("ayso-12u-boys").keeperMayPunt)
    }

    @Test func girlsAndBoysShareTheRulesButNotTheName() throws {
        let girls = try preset("ayso-12u-girls")
        let boys = try preset("ayso-12u-boys")
        #expect(girls.title == "AYSO 12U Girls")
        #expect(boys.title == "AYSO 12U Boys")
        #expect(girls.halfMinutes == boys.halfMinutes)
    }

    @Test func thePickerOffersTwelveYoungestFirstWithout7U() {
        #expect(MatchFormat.presets.count == 12)
        #expect(MatchFormat.presets.first?.title == "AYSO 8U Girls")
        #expect(MatchFormat.preset(id: "ayso-7u-girls") == nil)
        #expect(MatchFormat.presets.last?.title == "AYSO 19U Boys")
    }

    @Test func theRemindersSayWhatIsDifferent() throws {
        let u8 = try preset("ayso-8u-boys")
        #expect(u8.reminder == "7 v 7 (min 5) · size 3 ball · no score kept · all fouls IFK · no heading · no punts · build-out line · no offside · subs at quarters · no cards · half-time 5–10 min")
        #expect(u8.watchReminder == "No cards · no heading · all IFK · no offside · build-out")
        #expect(try preset("ayso-19u-girls").watchReminder == "11 v 11")
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

@Suite("age then gender")
struct AgeGenderTests {
    @Test func aDivisionIsAnAgeAndAGender() throws {
        let f = try #require(MatchFormat.preset(age: 12, gender: .boys))
        #expect(f.id == "ayso-12u-boys")
        #expect(f.age == 12)
        #expect(f.gender == .boys)
        #expect(MatchFormat.ageTitle(12) == "AYSO 12U")
        #expect(MatchFormat.preset(age: 7, gender: .girls) == nil)
        #expect(MatchFormat.presets.map(\.age) == [8, 8, 10, 10, 12, 12, 14, 14, 16, 16, 19, 19])
    }
}
