import Foundation
import Observation
import RefKit
import Security

/// The referee's CGI Sports schedule, read from the site into Matches (Kevin,
/// 2026-11-06: "Yes and can you auto add the link"). The parsing, and why it
/// can only read, is RefKit's `CGISchedule`; this is the fetching, the
/// Keychain, and when.
///
/// ! The link is a login (it opens the site signed in), so it lives in the
/// Keychain, this device only — not in UserDefaults, not in the backup, and
/// never shown whole. So do the username and password.
///
/// The link alone stops working after a while (Kevin, 2026-11-12: "it only
/// lasts for so long"), so with a username and password each check signs in
/// afresh (`CGILogin`) and reads with the session that comes back.
@MainActor @Observable final class ScheduleSync {
    private(set) var link: CGIScheduleLink?
    /// The username kept with a password; nil until the referee signs in.
    private(set) var userid: String?
    private(set) var checking = false
    private(set) var lastChecked: Date?
    /// "2 new matches", or what went wrong — the settings row's second line.
    private(set) var lastResult: String?

    /// Read again on opening the app once this much time has passed.
    static let every: TimeInterval = 3600

    init() {
        link = ScheduleKeychain.read().flatMap(CGIScheduleLink.init)
        userid = ScheduleKeychain.readLogin()?.userid
        lastChecked = UserDefaults.standard.object(forKey: "ref.schedule.lastChecked") as? Date
        lastResult = UserDefaults.standard.string(forKey: "ref.schedule.lastResult")
    }

    /// Keep a link the referee pasted or tapped. False when it is not a CGI
    /// Sports referee link.
    @discardableResult
    func connect(_ text: String) -> Bool {
        guard let parsed = CGIScheduleLink(text) else { return false }
        ScheduleKeychain.write(parsed.scheduleURL.absoluteString)
        link = parsed
        lastChecked = nil
        return true
    }

    /// Sign in with the site's username and password; kept only if the site
    /// accepts them. Nil on success, else what to tell the referee.
    func signIn(userid: String, password: String, store: PhoneStore) async -> String? {
        let login = CGILogin(region: link?.region ?? CGILogin.defaultRegion, userid: userid, password: password)
        guard !login.userid.isEmpty, !password.isEmpty else { return "Enter your username and password." }
        do {
            guard let fresh = try await signIn(login) else {
                return "CGI Sports didn't accept that username and password."
            }
            ScheduleKeychain.writeLogin(login)
            self.userid = login.userid
            remember(fresh)
        } catch {
            return "Couldn't reach cgisports.com."
        }
        lastChecked = nil
        await check(store)
        return nil
    }

    func disconnect() {
        ScheduleKeychain.delete()
        ScheduleKeychain.deleteLogin()
        link = nil
        userid = nil
        lastChecked = nil
        lastResult = nil
        UserDefaults.standard.removeObject(forKey: "ref.schedule.lastChecked")
        UserDefaults.standard.removeObject(forKey: "ref.schedule.lastResult")
    }

    func checkIfDue(_ store: PhoneStore) async {
        guard link != nil || userid != nil, !checking,
              Date().timeIntervalSince(lastChecked ?? .distantPast) > Self.every else { return }
        await check(store)
    }

    /// The schedule, then each upcoming game's page for its crew; new games
    /// become matches, and the crew and kick-off of ones not yet played follow
    /// the site.
    func check(_ store: PhoneStore) async {
        guard link != nil || userid != nil, !checking else { return }
        checking = true
        defer { checking = false }
        let result: String
        do {
            // A fresh session each time when there is a password to sign in with.
            if let login = ScheduleKeychain.readLogin() {
                if let fresh = try await signIn(login) { remember(fresh) }
                else { throw ScheduleError.refused }
            }
            guard let link else { throw ScheduleError.refused }
            let page = try await fetch(link.scheduleURL)
            let rows = CGISchedule.rows(page)
            if rows.isEmpty && !page.contains("ref_schedule") {
                result = userid == nil
                    ? "The saved link has expired — sign in with your username and password below."
                    : "Signed in, but the schedule didn't open."
            } else {
                var games: [ScheduledGame] = []
                for row in rows where row.isFuture {
                    let detail = try? await fetch(link.gameURL(row.gameID))
                    if let game = CGISchedule.game(row, page: detail) { games.append(game) }
                }
                let (new, updated) = store.importGames(games, followSite: true)
                result = Self.summary(upcoming: games.count, new: new, updated: updated)
            }
        } catch ScheduleError.refused {
            result = "CGI Sports didn't accept your password — sign in again."
        } catch {
            result = "Couldn't reach cgisports.com."
        }
        lastResult = result
        lastChecked = Date()
        UserDefaults.standard.set(lastChecked, forKey: "ref.schedule.lastChecked")
        UserDefaults.standard.set(result, forKey: "ref.schedule.lastResult")
    }

    static func summary(upcoming: Int, new: Int, updated: Int) -> String {
        var parts = ["\(upcoming) upcoming game\(upcoming == 1 ? "" : "s")"]
        if new > 0 { parts.append("\(new) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        return parts.joined(separator: " · ")
    }

    private enum ScheduleError: Error { case refused }

    private func remember(_ fresh: CGIScheduleLink) {
        ScheduleKeychain.write(fresh.scheduleURL.absoluteString)
        link = fresh
    }

    /// The site's login form; the new session, or nil when it was refused.
    private func signIn(_ login: CGILogin) async throws -> CGIScheduleLink? {
        var request = URLRequest(url: login.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(CGILogin.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = login.body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let page = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return login.link(fromPage: page, finalURL: response.url)
    }

    private func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // The site declares ISO-8859-1.
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

/// The schedule link's own Keychain item, apart from the account's key.
enum ScheduleKeychain {
    private static let service = "com.brisaloca.ref.cgi"

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        delete()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: Data(value.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
    }

    // The username and password: their own item, the region beside them.
    private static let loginService = "com.brisaloca.ref.cgi.login"

    static func readLogin() -> CGILogin? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: loginService,
                                    kSecReturnData as String: true,
                                    kSecReturnAttributes as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let found = item as? [String: Any],
              let data = found[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8),
              let account = found[kSecAttrAccount as String] as? String else { return nil }
        // "<region>/<userid>"
        let parts = account.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return CGILogin(region: parts[0], userid: parts[1], password: password)
    }

    static func writeLogin(_ login: CGILogin) {
        deleteLogin()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: loginService,
                                   kSecAttrAccount as String: "\(login.region)/\(login.userid)",
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: Data(login.password.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteLogin() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: loginService] as CFDictionary)
    }
}
