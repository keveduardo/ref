import Foundation
import Testing
@testable import RefKit

/// Signing in to CGI Sports (2026-11-12), with an invented user and password.
@Suite("CGI login")
struct CGILoginTests {
    /// The front page's own form, as a refused sign-in answers with it.
    static let refused = """
    <form id="form" name="form" action="https://cgisports.com/ref/5524/" method="post">
    <input type="hidden" name="user" id="user" value="">
    <input type="text" name="userid"><input type="password" name="password">
    <input class="btn btn-primary" type="submit" name="login" value="Login">
    <a href="https://cgisports.com/ref/5524?register=1&user=new_user">create a login account</a>
    """

    static let signedIn = """
    <a href="https://cgisports.com/ref/5524?register=1&user=new_user">x</a>
    <a href="https://cgisports.com/ref/5524?user=other.42&amp;view_schedule=1">x</a>
    <a href="https://cgisports.com/ref/5524?user=test.98765&amp;view_schedule=1">My Schedule</a>
    """

    @Test func theFormIsTheSitesOwn() {
        let login = CGILogin(userid: " test ", password: "p&ss word=1é")
        #expect(login.url.absoluteString == "https://cgisports.com/ref/5524/")
        let body = String(decoding: login.body, as: UTF8.self)
        #expect(body == "user=&ck=&userid=test&password=p%26ss+word%3D1%C3%A9&view_schedule=1&login=Login")
    }

    @Test func theNewSessionIsReadFromTheAnswer() {
        let link = CGILogin(userid: "Test", password: "x").link(fromPage: Self.signedIn)
        #expect(link?.user == "test.98765")
        #expect(link?.region == "5524")
        #expect(link?.scheduleURL.absoluteString == "https://cgisports.com/ref/5524/?user=test.98765&view_schedule=1")
    }

    @Test func whereTheAnswerLandedCountsFirst() {
        let landed = URL(string: "https://cgisports.com/ref/5524/?user=test.111&view_schedule=1")!
        let link = CGILogin(userid: "test", password: "x").link(fromPage: Self.signedIn, finalURL: landed)
        #expect(link?.user == "test.111")
    }

    @Test func aRefusedSignInHasNoSession() {
        #expect(CGILogin(userid: "test", password: "wrong").link(fromPage: Self.refused) == nil)
    }

    @Test func anotherRegion() {
        let login = CGILogin(region: "1234", userid: "test", password: "x")
        #expect(login.link(fromPage: Self.signedIn)?.scheduleURL.host == "cgisports.com")
        #expect(login.link(fromPage: Self.signedIn)?.region == "1234")
    }
}
