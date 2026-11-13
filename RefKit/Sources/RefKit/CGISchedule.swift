import Foundation

/// The referee's own CGI Sports schedule page, read straight from the site
/// (Kevin, 2026-11-06: "This is the link to my schedule ... Yes and can you
/// auto add the link"). Until then games came in by pasting a reminder email
/// (`ScheduledGame.parse`); the schedule page has every game at once.
///
/// ! THE LINK IS A LOGIN. `?user=<name>.<number>` opens the site signed in, no
/// password asked — it is kept in the phone's Keychain, never in a file, a
/// log or the backup, and the app shows only the region and name from it.
///
/// ! READ-ONLY, BY CONSTRUCTION. The schedule page and each game's page carry
/// links that change the assignment ("drop", "Make Request", the mentor box).
/// Only two URLs are ever built here — `scheduleURL` and `gameURL` — both
/// from fixed query items, and nothing in a fetched page is ever followed.
///
/// Two reads, and why: the schedule table has the games and the referee's
/// own position; each game's page adds the whole crew (CR, both ARs).
public struct CGIScheduleLink: Sendable, Equatable {
    /// The region's scheduler, "5524" for AYSO Region 34.
    public let region: String
    public let user: String

    /// From any page of the site the referee copied: it needs the host, a
    /// `/ref/<region>` path and the `user` item. Nil for anything else.
    public init?(_ text: String) {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(),
              host == "cgisports.com" || host == "www.cgisports.com",
              components.scheme == "https" || components.scheme == "http" else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "ref", parts[1].allSatisfy(\.isNumber),
              let user = components.queryItems?.first(where: { $0.name == "user" })?.value,
              !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
        else { return nil }
        self.region = String(parts[1])
        self.user = user
    }

    /// "keveduardo": the user name without its secret number, for the
    /// settings row.
    public var displayName: String { String(user.split(separator: ".").first ?? "") }

    private func url(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "cgisports.com"
        components.path = "/ref/\(region)/"
        components.queryItems = [URLQueryItem(name: "user", value: user)] + items
        return components.url!
    }

    /// My Schedule: every game the referee holds, past and future.
    public var scheduleURL: URL { url([URLQueryItem(name: "view_schedule", value: "1")]) }

    /// One game's page, which names the crew.
    public func gameURL(_ gameID: String) -> URL {
        url([URLQueryItem(name: "search_records", value: "1"), URLQueryItem(name: "id", value: gameID)])
    }
}

/// One row of My Schedule.
public struct CGIScheduleRow: Sendable, Equatable {
    public var gameID: String
    public var date: String
    public var time: String
    public var division: String
    /// "Alta Vista AVP" — the place and the field in one cell.
    public var location: String
    public var home: String
    public var visitor: String
    /// The referee's own slot: "Center", "AR", "AR1", "AR2", "4th".
    public var position: String
    /// The site marks each game past or future in its own link.
    public var isFuture: Bool
}

public enum CGISchedule {
    /// The rows of the `ref_schedule` table, in the page's order.
    public static func rows(_ html: String) -> [CGIScheduleRow] {
        guard let start = html.range(of: #"id="ref_schedule""#) else { return [] }
        let table = String(html[start.upperBound...])
        var rows: [CGIScheduleRow] = []
        // Each game row opens with the game's own link: id and past/future.
        for chunk in table.components(separatedBy: "<tr").dropFirst() {
            guard let id = first(#"[?&]id=(\d+)&(?:amp;)?my_game=(\w+)"#, in: chunk, groups: 2) else { continue }
            let cells = matches(#"<td[^>]*>(.*?)</td>"#, in: chunk).map(text)
            guard cells.count >= 8 else { continue }
            rows.append(CGIScheduleRow(gameID: id[0], date: cells[1], time: cells[2], division: cells[3],
                                       location: cells[4], home: cells[5], visitor: cells[6],
                                       position: cells[7], isFuture: id[1] == "future"))
        }
        return rows
    }

    /// A game's page: the crew by slot, "CR", "AR1", "AR2", "4th" — the ARs
    /// numbered in the page's order, as the site's own slot ids number them.
    /// An empty slot is left out.
    ///
    /// ! ONE ROW AT A TIME. Each slot's name is read only from its own table
    /// row. Searching the page from a slot's label to the next bold name
    /// put an AR in the centre's place whenever the centre was still open
    /// (Kevin, 2026-11-12: his 7 PM game showed him as CR, not AR).
    public static func crew(_ html: String) -> [String: String] {
        var crew: [String: String] = [:]
        var assistants = 0
        for row in html.components(separatedBy: "<tr").dropFirst() {
            let row = row.components(separatedBy: "</tr>").first ?? row
            guard let slot = first(#"title="[^"]+">\s*(CR|AR|4th|4TH)\s*</a>"#, in: row, groups: 1)?.first
            else { continue }
            let isAR = slot.uppercased() == "AR"
            // The AR count moves on for an open AR slot too: the second AR
            // row is AR2 whether or not the first is filled.
            if isAR { assistants += 1 }
            guard let name = first(#"<b[^>]*>(.*?)</b>"#, in: row, groups: 1).map({ text($0[0]) }),
                  !name.isEmpty else { continue }
            switch slot.uppercased() {
            case "CR": crew["CR"] = name
            case "AR": crew["AR\(assistants)"] = name
            default: crew["4th"] = name
            }
        }
        return crew
    }

    /// "Alta Vista&nbsp; -&nbsp; AVP" on a game's page → ("Alta Vista", "AVP").
    public static func venue(_ html: String) -> (location: String, field: String?)? {
        guard let line = first(#"<td align="center">([^<]*-[^<]*)</td>"#, in: html, groups: 1)?.first else { return nil }
        let parts = text(line).components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let place = parts.first, !place.isEmpty else { return nil }
        return (place, parts.count > 1 ? parts[1] : nil)
    }

    /// A row, and its game's page when it was read, as the game an email
    /// would have announced — the rest of the import is the email's.
    public static func game(_ row: CGIScheduleRow, page: String?, timeZone: TimeZone = .current) -> ScheduledGame? {
        guard let kickOff = ScheduledGame.kickOff(date: row.date, time: row.time, timeZone: timeZone) else { return nil }
        let crew = (page.map(crew) ?? [:]).filter { !$0.value.isEmpty }
        let venue = page.flatMap(venue)
        return ScheduledGame(gameID: row.gameID, division: row.division, kickOff: kickOff,
                             location: venue?.location ?? row.location, field: venue?.field,
                             home: row.home, visitor: row.visitor, crew: crew,
                             myRole: RefereeRole(scheduled: row.position), crewKnown: page != nil)
    }

    // MARK: - Text

    /// A cell's words: tags dropped, entities and runs of space collapsed.
    static func text(_ cell: String) -> String {
        var s = cell.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\""),
                               ("&lt;", "<"), ("&gt;", ">")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        all(pattern, in: text, groups: 1).map { $0[0] }
    }

    private static func first(_ pattern: String, in text: String, groups: Int) -> [String]? {
        all(pattern, in: text, groups: groups).first
    }

    private static func all(_ pattern: String, in text: String, groups: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1...groups).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}

/// Signing in with the referee's username and password, so the schedule keeps
/// working (Kevin, 2026-11-12: "after pasting in my schedule for ref it only
/// lasts for so long"). The number in `?user=<name>.<number>` is a session:
/// the site stops honouring it after a while, and a pasted link dies with it.
/// Each check signs in afresh and reads the new number out of the answer.
///
/// The form is the site's own front page (2026-11-12): a POST of `userid`,
/// `password` and `login=Login` to `/ref/<region>/`. Whatever page comes back
/// carries the new session in its links; a refused sign-in answers with the
/// login form again, whose only `user=` link is `new_user`.
///
/// ! THE PASSWORD. Built into a request body here and nowhere else — never a
/// URL, never a log. The app keeps it in the Keychain, this device only.
public struct CGILogin: Sendable, Equatable {
    /// AYSO Region 34's scheduler, used when no earlier link names another.
    public static let defaultRegion = "5524"

    public let region: String
    public let userid: String
    public let password: String

    public init(region: String = CGILogin.defaultRegion, userid: String, password: String) {
        self.region = region
        self.userid = userid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    public var url: URL { URL(string: "https://cgisports.com/ref/\(region)/")! }

    public static let contentType = "application/x-www-form-urlencoded"

    /// The form as the site's own page submits it.
    public var body: Data {
        let fields = [("user", ""), ("ck", ""), ("userid", userid), ("password", password),
                      ("view_schedule", "1"), ("login", "Login")]
        return Data(fields.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&").utf8)
    }

    /// The session the site handed back, from where the answer landed or any
    /// link in it. Nil when the sign-in was refused.
    public func link(fromPage html: String, finalURL: URL? = nil) -> CGIScheduleLink? {
        var candidates: [String] = []
        if let finalURL,
           let user = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "user" })?.value {
            candidates.append(user)
        }
        candidates += CGISchedule.sessions(in: html)
        // A session is "<name>.<digits>"; prefer the one for this username.
        let sessions = candidates.filter { CGILogin.isSession($0) }
        let mine = sessions.first { $0.split(separator: ".").first.map(String.init)?.lowercased() == userid.lowercased() }
        guard let user = mine ?? sessions.first else { return nil }
        return CGIScheduleLink("https://cgisports.com/ref/\(region)/?user=\(user)")
    }

    static func isSession(_ user: String) -> Bool {
        let parts = user.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty && parts[1].allSatisfy(\.isNumber)
    }

    /// x-www-form-urlencoded: letters, digits and `-._*` as they are, space
    /// as `+`, everything else as %XX of its UTF-8 bytes.
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "*"):
                out.append(Character(UnicodeScalar(byte)))
            case UInt8(ascii: " "):
                out.append("+")
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}

extension CGISchedule {
    /// Every `user=` value in a page's links, in order.
    static func sessions(in html: String) -> [String] {
        all(#"[?&](?:amp;)?user=([A-Za-z0-9._-]+)"#, in: html, groups: 1).map { $0[0] }
    }
}
