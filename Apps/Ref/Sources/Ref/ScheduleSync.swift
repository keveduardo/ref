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
/// never shown whole.
@MainActor @Observable final class ScheduleSync {
    private(set) var link: CGIScheduleLink?
    private(set) var checking = false
    private(set) var lastChecked: Date?
    /// "2 new matches", or what went wrong — the settings row's second line.
    private(set) var lastResult: String?

    /// Read again on opening the app once this much time has passed.
    static let every: TimeInterval = 3600

    init() {
        link = ScheduleKeychain.read().flatMap(CGIScheduleLink.init)
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

    func disconnect() {
        ScheduleKeychain.delete()
        link = nil
        lastChecked = nil
        lastResult = nil
        UserDefaults.standard.removeObject(forKey: "ref.schedule.lastChecked")
        UserDefaults.standard.removeObject(forKey: "ref.schedule.lastResult")
    }

    func checkIfDue(_ store: PhoneStore) async {
        guard link != nil, !checking,
              Date().timeIntervalSince(lastChecked ?? .distantPast) > Self.every else { return }
        await check(store)
    }

    /// The schedule, then each upcoming game's page for its crew; new games
    /// become matches, and the crew and kick-off of ones not yet played follow
    /// the site.
    func check(_ store: PhoneStore) async {
        guard let link, !checking else { return }
        checking = true
        defer { checking = false }
        let result: String
        do {
            let page = try await fetch(link.scheduleURL)
            let rows = CGISchedule.rows(page)
            if rows.isEmpty && !page.contains("ref_schedule") {
                result = "The link didn't open your schedule — copy it from the site again."
            } else {
                var games: [ScheduledGame] = []
                for row in rows where row.isFuture {
                    let detail = try? await fetch(link.gameURL(row.gameID))
                    if let game = CGISchedule.game(row, page: detail) { games.append(game) }
                }
                let (new, updated) = store.importGames(games, followSite: true)
                result = Self.summary(upcoming: games.count, new: new, updated: updated)
            }
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
}
