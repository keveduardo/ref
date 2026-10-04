import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import RefKit
import Security

/// The optional account: Sign in with Apple, then matches and team sheets
/// back up to reftime.brisaloca.com and sync between phones. Signed out,
/// nothing leaves the phone and the app works exactly as before.
///
/// ! What travels: a match's setup and timeline, and team sheets. Never the
/// health numbers (`metrics`) or anything located (`pitch`, routes) — App
/// Review is strict about health data leaving the device, and the privacy
/// page (reftime.brisaloca.com/privacy) promises it.
@MainActor @Observable final class AccountStore {
    static let server = URL(string: "https://reftime.brisaloca.com")!

    private(set) var signedIn = false
    private(set) var email: String?
    private(set) var provider: String?
    private(set) var syncing = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?

    @ObservationIgnored private weak var store: PhoneStore?
    @ObservationIgnored private var ledger: SyncLedger
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    /// The raw nonce for the sign-in in flight; Apple gets its SHA-256.
    @ObservationIgnored private var nonce: String?

    init() {
        ledger = SyncLedger.load()
        signedIn = Keychain.read() != nil
        email = UserDefaults.standard.string(forKey: "ref.account.email")
        provider = UserDefaults.standard.string(forKey: "ref.account.provider")
        lastSynced = UserDefaults.standard.object(forKey: "ref.account.lastSynced") as? Date
    }

    /// Wired once at launch: the store tells the account when it changed.
    func attach(_ store: PhoneStore) {
        self.store = store
        store.onChange = { [weak self] in self?.scheduleSync() }
        store.onDelete = { [weak self] kind, id in self?.noteDeleted(kind: kind, id: id) }
    }

    // MARK: - Sign in with Apple

    /// The request half of SignInWithAppleButton: ask for the email, and
    /// commit to a nonce so the token cannot be replayed elsewhere.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let raw = Self.randomNonce()
        nonce = raw
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(raw)
    }

    func complete(_ result: Result<ASAuthorization, any Error>) async {
        lastError = nil
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let nonce else {
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code != .canceled {
                lastError = "Sign in with Apple did not finish. Try again."
            }
            return
        }
        do {
            let response: SignInResponse = try await send("POST", "/v1/auth/apple",
                                                          body: ["identity_token": token, "nonce": nonce],
                                                          authorized: false)
            Keychain.write(response.key)
            signedIn = true
            email = response.email
            provider = response.provider
            UserDefaults.standard.set(response.email, forKey: "ref.account.email")
            UserDefaults.standard.set(response.provider, forKey: "ref.account.provider")
            // A fresh sign-in starts the ledger over: pull everything, then
            // push everything this phone has.
            ledger = SyncLedger()
            ledger.save()
            await sync()
        } catch {
            lastError = "Couldn't sign in: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        _ = try? await send("DELETE", "/v1/session", body: nil as [String: String]?) as Empty
        forget()
    }

    /// Deletes the account and everything backed up. What is on this phone
    /// stays. Apple requires the button for any app with accounts.
    func deleteAccount() async {
        do {
            _ = try await send("DELETE", "/v1/account", body: nil as [String: String]?) as Empty
            forget()
        } catch {
            lastError = "Couldn't delete the account: \(error.localizedDescription)"
        }
    }

    private func forget() {
        Keychain.delete()
        signedIn = false
        email = nil
        provider = nil
        lastSynced = nil
        ledger = SyncLedger()
        ledger.save()
        for key in ["ref.account.email", "ref.account.provider", "ref.account.lastSynced"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Sync

    /// A change on the phone: sync shortly, once, however many changes come.
    func scheduleSync() {
        guard signedIn else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func noteDeleted(kind: String, id: UUID) {
        guard signedIn else { return }
        ledger.tombstones.insert("\(kind):\(id.uuidString)")
        ledger.save()
    }

    /// Pull what changed elsewhere, then push what changed here. Last write
    /// wins, except that a local change not yet pushed is never overwritten.
    func sync() async {
        guard signedIn, let store, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            // Pull.
            let page: ItemsPage = try await send("GET", "/v1/items?since=\(ledger.lastPull)",
                                                 body: nil as [String: String]?)
            for item in page.items {
                let key = "\(item.kind):\(item.id.uuidString)"
                let local = localBody(kind: item.kind, id: item.id, in: store)
                let untouchedHere = local == nil || local.map(Self.hash) == ledger.pushed[key]
                if item.deleted {
                    if untouchedHere { store.removeFromSync(kind: item.kind, id: item.id) }
                    ledger.pushed[key] = nil
                } else if let body = item.body, untouchedHere {
                    store.applyFromSync(kind: item.kind, body: body)
                    ledger.pushed[key] = Self.hash(body)
                }
            }
            ledger.lastPull = max(ledger.lastPull, page.latest)

            // Push.
            var outgoing: [OutgoingItem] = ledger.tombstones.compactMap { key in
                let parts = key.split(separator: ":")
                guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
                return OutgoingItem(kind: String(parts[0]), id: id, body: nil, deleted: true)
            }
            for (kind, id, body) in localBodies(in: store) {
                let key = "\(kind):\(id.uuidString)"
                if ledger.pushed[key] != Self.hash(body) {
                    outgoing.append(OutgoingItem(kind: kind, id: id, body: body, deleted: false))
                }
            }
            for chunk in stride(from: 0, to: outgoing.count, by: 100).map({ Array(outgoing[$0..<min($0 + 100, outgoing.count)]) }) {
                let _: Empty = try await send("PUT", "/v1/items", body: ["items": chunk])
                for item in chunk {
                    let key = "\(item.kind):\(item.id.uuidString)"
                    if item.deleted {
                        ledger.tombstones.remove(key)
                        ledger.pushed[key] = nil
                    } else if let body = item.body {
                        ledger.pushed[key] = Self.hash(body)
                    }
                }
            }
            ledger.save()
            lastSynced = Date()
            lastError = nil
            UserDefaults.standard.set(lastSynced, forKey: "ref.account.lastSynced")
        } catch APIError.signedOut {
            forget()
            lastError = "Signed out — sign in again to keep backing up."
        } catch {
            ledger.save()
            lastError = "Backup will retry: \(error.localizedDescription)"
        }
    }

    // MARK: - What travels

    /// A match without its health numbers or its field's location; a team
    /// sheet as it is. Sorted keys, so the same thing always hashes the same.
    static func body(for match: Match) -> String? {
        var stripped = match
        stripped.metrics = nil
        stripped.pitch = nil
        return encode(stripped)
    }

    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func localBodies(in store: PhoneStore) -> [(String, UUID, String)] {
        var all: [(String, UUID, String)] = []
        for match in store.all { if let b = Self.body(for: match) { all.append(("match", match.id, b)) } }
        for squad in store.squads { if let b = Self.encode(squad) { all.append(("team", squad.id, b)) } }
        return all
    }

    private func localBody(kind: String, id: UUID, in store: PhoneStore) -> String? {
        switch kind {
        case "match": store.all.first { $0.id == id }.flatMap(Self.body(for:))
        case "team": store.squads.first { $0.id == id }.flatMap(Self.encode)
        default: nil
        }
    }

    static func hash(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The wire

    private enum APIError: LocalizedError {
        case signedOut
        case server(String)
        var errorDescription: String? {
            switch self {
            case .signedOut: "signed out"
            case .server(let message): message
            }
        }
    }

    private struct Empty: Decodable {}
    private struct SignInResponse: Decodable { let key: String; let provider: String; let email: String? }
    private struct ItemsPage: Decodable { let items: [IncomingItem]; let latest: Int64 }
    private struct IncomingItem: Decodable {
        let kind: String; let id: UUID; let deleted: Bool; let body: String?
    }
    private struct OutgoingItem: Encodable {
        let kind: String; let id: UUID; let body: String?; let deleted: Bool
    }
    private struct ServerError: Decodable { let error: String }

    private func send<B: Encodable, R: Decodable>(_ method: String, _ path: String, body: B?,
                                                   authorized: Bool = true) async throws -> R {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.server)!)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if authorized {
            guard let key = Keychain.read() else { throw APIError.signedOut }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && authorized { throw APIError.signedOut }
        guard (200..<300).contains(status) else {
            throw APIError.server((try? JSONDecoder().decode(ServerError.self, from: data))?.error
                                  ?? "server answered \(status)")
        }
        if R.self == Empty.self { return Empty() as! R }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// What has been synced: the newest server time pulled, a hash of what was
/// last pushed for each item, and deletions still to send. A file, so a
/// relaunch picks up where it left off.
struct SyncLedger: Codable {
    var lastPull: Int64 = 0
    var pushed: [String: String] = [:]
    var tombstones: Set<String> = []

    private static var url: URL {
        PhoneStore.directory.appendingPathComponent("sync-ledger.json")
    }

    static func load() -> SyncLedger {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncLedger.self, from: $0) } ?? SyncLedger()
    }

    func save() {
        try? FileManager.default.createDirectory(at: PhoneStore.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}

/// The device key, in the Keychain — this device only, never in a backup.
enum Keychain {
    private static let service = "com.brisaloca.ref.account"

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String) {
        delete()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: Data(key.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
    }
}
