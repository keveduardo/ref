import Foundation
import Testing
@testable import RefKit

/// The shapes of CGI Sports' My Schedule and game pages (2026-11-06), with
/// invented names and an invented user — the real link is a login.
@Suite("CGI schedule")
struct CGIScheduleTests {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static let schedule = """
    <table width="100%" cellpadding="3" border="0" cellspacing="2" id="ref_schedule" style="font-size:90%">
        <tr bgcolor="#D3D3D3">
        <td>Game ID</td>
        <td><a href="https://cgisports.com/ref/5524?user=test.123&view_schedule=1&sb=date&so=ASC">Date</a> &nbsp;</td>
        <td>Time</td><td>Division</td><td>Location</td><td>Home</td><td>Visitor</td><td>Position</td><td>Team Credited</td>
        <td colspan="3">Request Date</td>
        </tr>
            <tr bgcolor='#D8E2F5'>
            <td><a href="https://cgisports.com/ref/5524?user=test.123&search_records=1&id=12043&my_game=future">12043</a></td>
            <td>Nov 6, 2026</td>
            <td>6:30 PM</td>
            <td>Boys 12U</td>
            <td>Alta Vista AVP</td>
            <td>08 Garcia</td>
            <td>05 Lopez</td>
            <td>AR</td>
            <td><span id="single-12043"></span></td>
            <td align="center" colspan="3" id="response-12043" class="f85"> <table width="100%"><tr><td colspan="3">11/5/26 7:26 PM</td></tr></table> </td>
            </tr>
            <tr bgcolor='#EAEAEA'>
            <td><a href="https://cgisports.com/ref/5524?user=test.123&search_records=1&id=10031&my_game=past">10031</a></td>
            <td>Oct 4, 2026</td>
            <td>9:15 AM</td>
            <td>Boys 10U</td>
            <td>Alta Vista AVS</td>
            <td>03 Chen</td>
            <td>04 Patel</td>
            <td>Center</td>
            <td><span id="single-10031">R34 Volunteer</span></td>
            <td align="center" colspan="3" id="response-10031" class="f85"> <table width="100%"><tr><td colspan="3">10/3/26 6:35 PM</td></tr></table> </td>
            </tr>
            </table>
    """

    static let game = """
    <table align="center" border="0" cellpadding="1" cellspacing="0" width="100%">
        <tr><td align="center">Game 12043:
        Boys 12U
        </td></tr>
        <tr><td align="center"><u>Fri Nov 6, 2026 - 6:30 PM</u></td></tr>
        <tr><td align="center">Alta Vista&nbsp; -&nbsp; AVP</td></tr>
        <tr><td class="med" align="center">08 Garcia vs 05 Lopez</td></tr>
    </table>
    <table width="100%" align="center" cellspacing="3" cellpadding="3">
        <tr bgcolor="#E9E9E9">
        <td width="20%" align="center" height="30" class="tip"><a href="#" title="Center Referee">CR</a>: </td><td align="left"><b>Alex Rivera</b>&nbsp;&nbsp;<span class="med"></span>  Reg   </td>
        </tr>
        <tr bgcolor="#E9E9E9">
        <td align="center" height="30" class="tip"><a href="#" title="Assistant Referee">AR</a>: </td><td align="left"><b class="cancel_tip">Sam Lee</b>&nbsp;&nbsp;<span class="med"></span>  Reg   </td>
        </tr>
        <tr bgcolor="#E9E9E9">
        <td align="center" height="30" class="tip"><a href="#" title="Assistant Referee">AR</a>: </td><td align="left"><b class="cancel_tip">Pat Referee</b>&nbsp;&nbsp;<span class="med"></span>   <span class="drop tip" id="12043-ar2" data-m_requested="0"><a href="#" title="Click to drop this assignment">drop</a></span></td>
        </tr>
    </table>
    """

    @Test func theLinkIsReadFromAnyPageAndRebuiltReadOnly() throws {
        let link = try #require(CGIScheduleLink("https://cgisports.com/ref/5524/?user=test.123&view_schedule=1"))
        #expect(link.region == "5524" && link.user == "test.123" && link.displayName == "test")
        #expect(link.scheduleURL.absoluteString == "https://cgisports.com/ref/5524/?user=test.123&view_schedule=1")
        #expect(link.gameURL("12043").absoluteString == "https://cgisports.com/ref/5524/?user=test.123&search_records=1&id=12043")
        #expect(CGIScheduleLink("https://cgisports.com/ref/5524?user=test.123&search=1") != nil)
        #expect(CGIScheduleLink("https://evil.example/ref/5524/?user=test.123") == nil)
        #expect(CGIScheduleLink("https://cgisports.com/ref/5524/") == nil)
        #expect(CGIScheduleLink("https://cgisports.com/ref/5524/?user=a%26drop%3D1") == nil)
    }

    @Test func theScheduleTableIsEveryGameWithItsPosition() {
        let rows = CGISchedule.rows(Self.schedule)
        #expect(rows.map(\.gameID) == ["12043", "10031"])
        #expect(rows[0] == CGIScheduleRow(gameID: "12043", date: "Nov 6, 2026", time: "6:30 PM", division: "Boys 12U",
                                          location: "Alta Vista AVP", home: "08 Garcia", visitor: "05 Lopez",
                                          position: "AR", isFuture: true))
        #expect(rows[1].position == "Center" && !rows[1].isFuture)
        #expect(CGISchedule.rows("<html>signed out</html>").isEmpty)
    }

    @Test func aGamesPageNamesTheCrewAndTheField() throws {
        #expect(CGISchedule.crew(Self.game) == ["CR": "Alex Rivera", "AR1": "Sam Lee", "AR2": "Pat Referee"])
        let venue = try #require(CGISchedule.venue(Self.game))
        #expect(venue.location == "Alta Vista" && venue.field == "AVP")
    }

    /// The 7 PM game of 2026-11-13: no centre yet, the referee is AR1.
    /// The open slot's row has no name, and must not borrow the next one.
    static let openCentre = """
    <table width="100%" align="center" cellspacing="3" cellpadding="3">
        <tr bgcolor="#E9E9E9">
        <td width="20%" align="center" height="30" class="tip"><a href="#" title="Center Referee">CR</a>: </td><td align="left"><span class="request tip"><a href="#" title="Click to request">Make Request</a></span></td>
        </tr>
        <tr bgcolor="#E9E9E9">
        <td align="center" height="30" class="tip"><a href="#" title="Assistant Referee">AR</a>: </td><td align="left"><b class="cancel_tip">Pat Referee</b>&nbsp;&nbsp;<span class="drop tip"><a href="#" title="Click to drop this assignment">drop</a></span></td>
        </tr>
        <tr bgcolor="#E9E9E9">
        <td align="center" height="30" class="tip"><a href="#" title="Assistant Referee">AR</a>: </td><td align="left"><b class="cancel_tip">Sam Lee</b></td>
        </tr>
    </table>
    """

    @Test func anOpenSlotStaysOpen() {
        #expect(CGISchedule.crew(Self.openCentre) == ["AR1": "Pat Referee", "AR2": "Sam Lee"])
        // An open first AR leaves the second as AR2.
        let openAR1 = Self.openCentre.replacingOccurrences(of: #"<b class="cancel_tip">Pat Referee</b>"#, with: "")
        #expect(CGISchedule.crew(openAR1) == ["AR2": "Sam Lee"])
    }

    @Test func aRowAndItsPageMakeTheMatch() throws {
        let row = CGISchedule.rows(Self.schedule)[0]
        let game = try #require(CGISchedule.game(row, page: Self.game, timeZone: Self.pacific))
        let setup = game.matchSetup()
        #expect(setup.cr == "Alex Rivera" && setup.ar1 == "Sam Lee" && setup.ar2 == "Pat Referee")
        // The schedule's Position column is the referee's own slot.
        #expect(setup.myRole == .ar)
        #expect(CGISchedule.game(CGISchedule.rows(Self.schedule)[1], page: nil)?.myRole == .cr)
        #expect(setup.home.number == "08" && setup.home.coach == "Garcia")
        #expect(setup.format?.id == "ayso-12u-boys")
        #expect(game.venue == "Alta Vista · AVP")
        // The same game from an email and from the site is one match.
        #expect(setup.id == ScheduledGame.matchID("12043"))

        // Without its page: the row alone, and no crew names.
        let bare = try #require(CGISchedule.game(row, page: nil, timeZone: Self.pacific))
        #expect(bare.crew.isEmpty && bare.location == "Alta Vista AVP")
    }
}
