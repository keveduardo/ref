import Foundation
import Testing
@testable import RefKit

/// The layout of CGI Sports' "Game reminder" email, with invented names.
@Suite("schedule import")
struct ScheduleImportTests {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static let reminder = """
        hello Pat Referee,
    This message is being sent as a reminder from the Referee Scheduling System:

    *************************************************************************************You have a game coming up soon! Below are the details

    Game ID: 120107
    CR: Pat Referee
    AR1: Sam Assistant
    AR2:
    Division: BC Boys 12U
    Date: Nov 16, 2025 Sun
    Time: 8:00 AM
    Location: Alta Vista
    Field: AVP
    Home: A1 02 Smith
    Visitor: A2 07 Jones
    **************************************************************************************
    Please make every attempt to cover the games you have signed up to do. &nbsp; &nbsp;
    """

    @Test func aReminderBecomesAGame() throws {
        let games = ScheduledGame.parse(Self.reminder, timeZone: Self.pacific)
        let game = try #require(games.first)
        #expect(games.count == 1)
        #expect(game.gameID == "120107")
        #expect(game.home == "A1 02 Smith")
        #expect(game.visitor == "A2 07 Jones")
        #expect(game.venue == "Alta Vista · AVP")
        #expect(game.crew == ["CR": "Pat Referee", "AR1": "Sam Assistant"])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.pacific
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: game.kickOff)
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2025, 11, 16, 8, 0])
    }

    @Test func theDivisionPicksTheAYSOPreset() throws {
        let game = try #require(ScheduledGame.parse(Self.reminder, timeZone: Self.pacific).first)
        #expect(game.format?.id == "ayso-12u-boys")

        let setup = game.matchSetup()
        #expect(setup.formatID == "ayso-12u-boys")
        #expect(setup.clock.halfLength == TimeInterval(30 * 60))
        #expect(setup.clock.countsDown)
        #expect(setup.home.abbreviation == "SMI")
        #expect(setup.away.abbreviation == "JON")
        #expect(setup.competition == "AYSO 12U Boys — Alta Vista · AVP")
    }

    @Test func divisionsAreReadHoweverTheyAreWritten() {
        func preset(_ division: String) -> String? {
            ScheduledGame(gameID: "1", division: division, kickOff: Date(), location: nil,
                          field: nil, home: "H", visitor: "V", crew: [:]).format?.id
        }
        #expect(preset("Girls 10U") == "ayso-10u-girls")
        #expect(preset("U14 Boys") == "ayso-14u-boys")
        #expect(preset("10UG") == "ayso-10u-girls")
        #expect(preset("BC Girls 14U") == "ayso-14u-girls")
        #expect(preset("Boys 16U") == "ayso-16u-boys")
        // An age RefTime has no preset for, or no gender: no preset, no guess.
        #expect(preset("Boys 15U") == nil)
        #expect(preset("Coed 10U") == nil)
    }

    @Test func importingTheSameGameTwiceIsOneMatch() throws {
        let a = try #require(ScheduledGame.parse(Self.reminder).first).matchSetup()
        let b = try #require(ScheduledGame.parse(Self.reminder).first).matchSetup()
        #expect(a.id == b.id)
        #expect(a.id.uuidString.hasSuffix("000000120107"))
    }

    @Test func severalGamesInOnePasteAndJunkIsSkipped() {
        let second = Self.reminder
            .replacingOccurrences(of: "120107", with: "120200")
            .replacingOccurrences(of: "8:00 AM", with: "10:30 AM")
        let broken = "Game ID: 999\nHome: Only one team\n"
        let games = ScheduledGame.parse(Self.reminder + second + broken, timeZone: Self.pacific)
        #expect(games.map(\.gameID) == ["120107", "120200"])
        #expect(ScheduledGame.parse("just some text").isEmpty)
    }
}
